ACTION_SERVER_DOCKERPATH ?= financial-demo:test
ACTION_SERVER_DOCKERNAME ?= financial-demo
ACTION_SERVER_PORT ?= 5056
ACTION_SERVER_ENDPOINT_HEALTH ?= health

RASA_MODEL_NAME ?= `git branch --show-current`
RASA_MODEL_PATH ?= models/`git branch --show-current`.tar.gz

# The CICD pipeline sets these as environment variables 
# Set some defaults for when you're running locally
AWS_REGION ?= us-west-2
AWS_ECR_URI ?= 024629701212.dkr.ecr.us-west-2.amazonaws.com
AWS_S3_NAME ?= rasa-financial-demo
AWS_STACK_NAME ?= financial-demo-$(USER)-test
AWS_STACK_TYPE ?= $(USER)-test

help:
	@echo "make"
	@echo "	clean"
	@echo "		Remove Python/build artifacts."
	@echo "	formatter"
	@echo "		Apply black formatting to code."
	@echo "	lint"
	@echo "		Lint code with flake8, and check if black formatter should be applied."
	@echo "	types"
	@echo "		Check for type errors using pytype."
	@echo "	test"
	@echo "		Run unit tests for the custom actions using pytest."
	@echo "	docker-build"
	@echo "		Builds docker image of the action server"
	@echo "	docker-run"
	@echo "		Runs the docker image of the action server"
	@echo "	docker-stops"
	@echo "		Stops the running docker container of the action server"
	@echo "	docker-test"
	@echo "		Tests the health endpoint of the action server"
	@echo "	docker-clean-container"
	@echo "		Stops & removes the container of the action server"
	@echo "	docker-clean-image"
	@echo "		Removes the docker image of the action server"
	@echo "	docker-clean"
	@echo "		Runs `docker-clean-container` and `docker-clean-image`"
	@echo "	docker-login"
	@echo "		Logs docker into container registry with DOCKER_USER & DOCKER_PW"
	@echo "	docker-push"
	@echo "		Pushes docker images to the logged in container registry"
	@echo "	aws-deploy-stack"
	@echo "		Deploys/updates the aws stack using a CloudFormation template."
	@echo "	aws-delete-stack"
	@echo "		Deletes an aws stack using a CloudFormation template."

clean:
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f  {} +
	rm -rf build/
	rm -rf .pytype/
	rm -rf dist/
	rm -rf docs/_build

formatter:
	black actions

lint:
	flake8 actions
	black --check actions 

types:
	pytype --keep-going actions

test:
	pytest tests
	
docker-build:
	docker build . --file Dockerfile --tag $(ACTION_SERVER_DOCKERPATH)
	
docker-run:
	docker run -d -p $(ACTION_SERVER_PORT):5055 --name $(ACTION_SERVER_DOCKERNAME) $(ACTION_SERVER_DOCKERPATH)
	
docker-test:
	curl http://localhost:$(ACTION_SERVER_PORT)/$(ACTION_SERVER_ENDPOINT_HEALTH)
	@echo $(NEWLINE)

docker-stop:
	docker stop $(ACTION_SERVER_DOCKERNAME)
	
docker-clean-container:
	docker stop $(ACTION_SERVER_DOCKERNAME)
	docker rm $(ACTION_SERVER_DOCKERNAME)
	
docker-clean-image:
	docker rmi $(ACTION_SERVER_DOCKERPATH)

docker-clean: docker-clean-container docker-clean-image
	
docker-login:
	@echo docker registry: $(DOCKER_REGISTRY)
	@echo docker user: $(DOCKER_USER)
	@echo $(DOCKER_PW) | docker login $(DOCKER_REGISTRY) -u $(DOCKER_USER) --password-stdin

docker-push:
	@echo pushing image: $(ACTION_SERVER_DOCKERPATH)
	docker image push $(ACTION_SERVER_DOCKERPATH)

aws-docker-login:
	@ echo Retrieving an authentication token and authenticating Docker client to the registry.
	@echo logging into AWS ECR registry: $(AWS_ECR_URI)
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ECR_URI)
	
aws-s3-create:
	@echo creating s3 bucket: $(AWS_S3_NAME)
	aws s3api create-bucket \
		--bucket $(AWS_S3_NAME) \
		--region $(AWS_REGION) \
		--create-bucket-configuration LocationConstraint=$(AWS_REGION)

aws-s3-delete:
	@echo deleting s3 bucket: $(AWS_S3_NAME)
	aws s3 rb s3://$(AWS_S3_NAME) --force

aws-s3-copy-rasa-model:
	@echo copying $(RASA_MODEL_PATH) to s3://$(AWS_S3_NAME)/$(RASA_MODEL_PATH)
	aws s3 cp $(RASA_MODEL_PATH) s3://$(AWS_S3_NAME)/$(RASA_MODEL_PATH)
	
aws-deploy-stack:
	@echo deploying the AWS CloudFormation Stack with name: $(AWS_STACK_NAME)
	@echo $(NEWLINE)
	aws cloudformation deploy \
		--template-file aws/cloudformation/aws-deploy-stack.yml \
		--tags findemo_stack_type=$(AWS_STACK_TYPE) \
		--stack-name $(AWS_STACK_NAME) \
		--parameter-overrides StackName=$(AWS_STACK_NAME)
		
aws-delete-stack:
	@echo deleting the AWS CloudFormation Stack with name: $(AWS_STACK_NAME)
	@echo $(NEWLINE)
	aws cloudformation delete-stack --stack-name $(AWS_STACK_NAME)
	
rasa-train:
	@echo Training $(RASA_MODEL_NAME)
	rasa train --fixed-model-name $(RASA_MODEL_NAME)
	
rasa-test:
	@echo Testing $(RASA_MODEL_PATH)
	rasa test --model $(RASA_MODEL_PATH)