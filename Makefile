ACTION_SERVER_DOCKERPATH := financial-demo:test
ACTION_SERVER_DOCKERNAME := financial-demo
ACTION_SERVER_PORT := 5056
ACTION_SERVER_ENDPOINT_HEALTH := health

RASA_MODEL_NAME := $(shell git branch --show-current)
RASA_MODEL_PATH := models/$(shell git branch --show-current).tar.gz

# The CICD pipeline sets these as environment variables 
# Set some defaults for when you're running locally
AWS_REGION := us-west-2

AWS_ECR_REPOSITORY := financial-demo

AWS_S3_BUCKET_NAME := rasa-financial-demo

AWS_IAM_ROLE_NAME := eksClusterRole

#AWS_EKS_VPC_STACK_NAME := eks-vpc-financial-demo-$(shell git branch --show-current)
AWS_EKS_VPC_TEMPLATE := aws/cloudformation/amazon-eks-vpc-private-subnets.yaml
AWS_EKS_KEYPAIR_NAME := findemo
AWS_EKS_CLUSTER_NAME := financial-demo-$(shell git branch --show-current)
AWS_EKS_KUBERNETES_VERSION := 1.19

AWS_EKS_NAMESPACE := my-namespace
AWS_EKS_RELEASE_NAME := my-release

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

clean:
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f  {} +
	rm -rf build/
	rm -rf .pytype/
	rm -rf dist/
	rm -rf docs/_build

install-eksctl:
	curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/0.43.0-rc.0/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
	sudo mv /tmp/eksctl /usr/local/bin
	@echo $(NEWLINE)
	eksctl version
	@echo $(NEWLINE)
	@echo Note: we require 0.43.0-rc.0 or higher
	
install-kubectl:
	sudo snap install kubectl --classic
	@echo $(NEWLINE)
	sudo kubectl version --client --short

install-helm:
	sudo snap install helm --classic
	@echo $(NEWLINE)
	helm version --short
	
rasa-train:
	@echo Training $(RASA_MODEL_NAME)
	rasa train --fixed-model-name $(RASA_MODEL_NAME)
	
rasa-test:
	@echo Testing $(RASA_MODEL_PATH)
	rasa test --model $(RASA_MODEL_PATH)
	
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
		
aws-iam-role-get-Arn:	
	@aws iam get-role \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--role-name $(AWS_IAM_ROLE_NAME) \
		--query "Role.Arn"
		
aws-ecr-docker-login:
	@$(eval AWS_ECR_URI := $(shell make aws-ecr-get-repositoryUri))
	@echo logging into AWS ECR registry: $(AWS_ECR_URI)
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ECR_URI)
	
aws-ecr-create-repository:
	@echo creating ecr repository: $(AWS_ECR_REPOSITORY)
	@echo $(NEWLINE)
	aws ecr create-repository \
		--repository-name $(AWS_ECR_REPOSITORY) \
		--region $(AWS_REGION)

aws-ecr-get-authorization-token:	
	@aws ecr get-authorization-token \
		--no-paginate \
		--output text \
		--region=$(AWS_REGION) \
		--query authorizationData[].authorizationToken | base64 -d | cut -d: -f2
		
aws-ecr-get-repositoryUri:	
	@aws ecr describe-repositories \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--repository-names $(AWS_ECR_REPOSITORY) \
		--query "repositories[].repositoryUri"
		
aws-s3-create-bucket:
	@echo creating s3 bucket: $(AWS_S3_BUCKET_NAME)
	@echo $(NEWLINE)
	aws s3api create-bucket \
		--bucket $(AWS_S3_BUCKET_NAME) \
		--region $(AWS_REGION) \
		--create-bucket-configuration LocationConstraint=$(AWS_REGION)

aws-s3-delete-bucket:
	@echo deleting s3 bucket: $(AWS_S3_BUCKET_NAME)
	aws s3 rb s3://$(AWS_S3_BUCKET_NAME) --force

aws-s3-copy-rasa-model:
	@echo copying $(RASA_MODEL_PATH) to s3://$(AWS_S3_BUCKET_NAME)/$(RASA_MODEL_PATH)
	aws s3 cp $(RASA_MODEL_PATH) s3://$(AWS_S3_BUCKET_NAME)/$(RASA_MODEL_PATH)

#aws-cloudformation-eks-vpc-stack-exists:
#	@aws cloudformation describe-stacks \
#		--no-paginate \
#		--output text \
#		--region $(AWS_REGION) \
#		--query "contains(Stacks[*].StackName, '$(AWS_EKS_VPC_STACK_NAME)')"	
		
#aws-cloudformation-eks-vpc-stack-deploy:
#	@aws cloudformation deploy \
#		--stack-name $(AWS_EKS_VPC_STACK_NAME) \
#		--template-file $(AWS_EKS_VPC_TEMPLATE)

#aws-cloudformation-eks-vpc-stack-status:	
#	@aws cloudformation describe-stacks \
#		--no-paginate \
#		--output text \
#		--region $(AWS_REGION) \
#		--stack-name $(AWS_EKS_VPC_STACK_NAME) \
#		--query "Stacks[].StackStatus"
		
aws-cloudformation-eks-get-SubnetsPrivate:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='SubnetsPrivate'].OutputValue"
		
aws-cloudformation-eks-get-SubnetsPublic:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='SubnetsPublic'].OutputValue"
		
aws-cloudformation-eks-get-ServiceRoleARN:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='ServiceRoleARN'].OutputValue"
		
aws-cloudformation-eks-get-Endpoint:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='Endpoint'].OutputValue"
		
aws-cloudformation-eks-get-SharedNodeSecurityGroup:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='SharedNodeSecurityGroup'].OutputValue"

aws-cloudformation-eks-get-VPC:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='VPC'].OutputValue"

aws-cloudformation-eks-get-ClusterSecurityGroupId:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='ClusterSecurityGroupId'].OutputValue"

aws-cloudformation-eks-get-CertificateAuthorityData:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='CertificateAuthorityData'].OutputValue"

aws-cloudformation-eks-get-SecurityGroup:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='SecurityGroup'].OutputValue"

aws-cloudformation-eks-get-ARN:	
	@aws cloudformation describe-stacks \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--stack-name eksctl-$(AWS_EKS_CLUSTER_NAME)-cluster \
		--query "Stacks[].Outputs[?OutputKey=='ARN'].OutputValue"
	
aws-eks-cluster-create:		
	eksctl create cluster \
		--name $(AWS_EKS_CLUSTER_NAME) \
		--region $(AWS_REGION) \
		--version $(AWS_EKS_KUBERNETES_VERSION) \
		--with-oidc \
		--ssh-access \
		--ssh-public-key $(AWS_EKS_KEYPAIR_NAME) \
		--managed

aws-eks-cluster-info:
	kubectl cluster-info
	
# https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html
aws-eks-cluster-delete:
	eksctl delete cluster \
		--name $(AWS_EKS_CLUSTER_NAME) \
		--region $(AWS_REGION) 
	@echo $(NEWLINE)
	@echo See AWS CloudFormation Console. The stack deletion is still in progress...

aws-eks-cluster-exists:
	@aws eks list-clusters \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--query "contains(clusters[*], '$(AWS_EKS_CLUSTER_NAME)')"	
			
#aws-eks-cluster-create-OLD:
#	@$(eval AWS_EKS_CLUSTER_ROLE_ARN := $(shell make aws-iam-role-get-Arn))
#	@$(eval AWS_EKS_SECURITY_GROUP_IDS := $(shell make aws-cloudformation-eks-vpc-get-SecurityGroups))
#	@$(eval AWS_EKS_SUBNET_IDS=$(shell make aws-cloudformation-eks-vpc-get-SubnetIds))
#	@echo Creating an AWS EKS cluster with:
#	@echo - AWS_EKS_CLUSTER_NAME              : $(AWS_EKS_CLUSTER_NAME)
#	@echo - AWS_EKS_CLUSTER_ROLE_ARN      : $(AWS_EKS_CLUSTER_ROLE_ARN)
#	@echo - AWS_EKS_SECURITY_GROUP_IDS: $(AWS_EKS_SECURITY_GROUP_IDS)
#	@echo - AWS_EKS_SUBNET_IDS        : $(AWS_EKS_SUBNET_IDS)
#	@echo $(NEWLINE)
#	aws eks create-cluster \
#		--no-paginate \
#		--output text \
#		--region $(AWS_REGION) \
#		--name $(AWS_EKS_CLUSTER_NAME) \
#		--kubernetes-version $(AWS_EKS_KUBERNETES_VERSION) \
#		--role-arn $(AWS_EKS_CLUSTER_ROLE_ARN) \
#		--resources-vpc-config subnetIds=$(AWS_EKS_SUBNET_IDS),securityGroupIds=$(AWS_EKS_SECURITY_GROUP_IDS)		

#aws-eks-wait-cluster-active:	
#	@aws eks wait cluster-active \
#		--region $(AWS_REGION) \
#		--name $(AWS_EKS_CLUSTER_NAME)
		
aws-eks-cluster-describe:	
	@aws eks describe-cluster \
		--no-paginate \
		--region $(AWS_REGION) \
		--name $(AWS_EKS_CLUSTER_NAME) 
		
aws-eks-cluster-describe-stacks:	
	@eksctl utils describe-stacks \
		--region $(AWS_REGION) \
		--cluster $(AWS_EKS_CLUSTER_NAME) 
		
aws-eks-cluster-status:	
	@aws eks describe-cluster \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--name $(AWS_EKS_CLUSTER_NAME) \
		--query "cluster.status"	

aws-eks-cluster-get-endpoint:
	@aws eks describe-cluster \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--name $(AWS_EKS_CLUSTER_NAME) \
		--query "cluster.endpoint"

aws-eks-cluster-get-certificateAuthority:
	@aws eks describe-cluster \
		--no-paginate \
		--output text \
		--region $(AWS_REGION) \
		--name $(AWS_EKS_CLUSTER_NAME) \
		--query "cluster.certificateAuthority"

aws-eks-cluster-update-kubeconfig:
	@echo Updating kubeconfig for AWS EKS cluster with name: $(AWS_EKS_CLUSTER_NAME)
	@echo $(NEWLINE)
	aws eks update-kubeconfig \
		--region $(AWS_REGION) \
		--name $(AWS_EKS_CLUSTER_NAME)	

aws-eks-namespace-create:
	kubectl create namespace $(AWS_EKS_NAMESPACE)
	
aws-eks-namespace-delete:
	kubectl delete namespace $(AWS_EKS_NAMESPACE)
	
	
pull-secret-gcr-create:
	@echo "Creating pull secret for Rasa Enterprise (in GCR)"
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		delete secret gcr-pull-secret \
		--ignore-not-found
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		create secret docker-registry gcr-pull-secret \
		--docker-server=gcr.io \
		--docker-username=_json_key \
		--docker-password='$(shell cat ./secret/gcr-auth.json)'
		
pull-secret-gcr-delete:
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		delete secret gcr-pull-secret \
		--ignore-not-found

pull-secret-ecr-create:
	@echo "Creating pull secret for Action Server (in ECR)"
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		delete secret ecr-pull-secret \
		--ignore-not-found

	@$(eval AWS_ECR_TOKEN := $(shell make aws-ecr-get-repositoryUri))
	@$(eval AWS_ECR_URI := $(shell make aws-ecr-get-repositoryUri))
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		create secret docker-registry ecr-pull-secret \
		--docker-server=https://$(AWS_ECR_URI) \
		--docker-username=AWS \
		--docker-password="$(AWS_ECR_TOKEN)"
		
pull-secret-ecr-delete:
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		delete secret ecr-pull-secret \
		--ignore-not-found
		

rasa-enterprise-install:
	@[ "${RASAX_TAG}" ]								|| ( echo ">> RASAX_TAG is not set"; exit 1 )
	@[ "${RASAX_INITIALUSER_USERNAME}" ]			|| ( echo ">> RASAX_INITIALUSER_USERNAME is not set"; exit 1 )
	@[ "${RASAX_INITIALUSER_PASSWORD}" ]			|| ( echo ">> RASAX_INITIALUSER_PASSWORD is not set"; exit 1 )
	@[ "${RASAX_PASSWORDSALT}" ]					|| ( echo ">> RASAX_PASSWORDSALT is not set"; exit 1 )
	@[ "${RASAX_TOKEN}" ]							|| ( echo ">> RASAX_TOKEN is not set"; exit 1 )
	@[ "${RASAX_JWTSECRET}" ]						|| ( echo ">> RASAX_JWTSECRET is not set"; exit 1 )
	@[ "${RASA_TAG}" ]								|| ( echo ">> RASA_TAG is not set"; exit 1 )
	@[ "${RASA_TOKEN}" ]							|| ( echo ">> RASA_TOKEN is not set"; exit 1 )
	@[ "${RABBITMQ_RABBITMQ_PASSWORD}" ]			|| ( echo ">> RABBITMQ_RABBITMQ_PASSWORD is not set"; exit 1 )
	@[ "${GLOBAL_POSTGRESQL_POSTGRESQLPASSWORD}" ]	|| ( echo ">> GLOBAL_POSTGRESQL_POSTGRESQLPASSWORD is not set"; exit 1 )
	@[ "${GLOBAL_REDIS_PASSWORD}" ]					|| ( echo ">> GLOBAL_REDIS_PASSWORD is not set"; exit 1 )
	@[ "${APP_NAME}" ]								|| ( echo ">> APP_NAME is not set"; exit 1 )
	@[ "${APP_TAG}" ]								|| ( echo ">> APP_TAG is not set"; exit 1 )

	helm repo add rasa-x https://rasahq.github.io/rasa-x-helm
	helm repo update

	@echo $(NEWLINE)
	@echo Installing Rasa Enterprise with:
	@echo - RASAX_TAG: $(RASAX_TAG)
	@echo - RASA_TAG: $(RASA_TAG)
	@echo - APP_NAME: $(APP_NAME)
	@echo - APP_TAG: $(APP_TAG)
	@echo $(NEWLINE)
	@helm --namespace $(AWS_EKS_NAMESPACE) \
		install $(AWS_EKS_RELEASE_NAME)\
		--values ./deploy/values.yml \
		--set rasax.tag=$(RASAX_TAG) \
		--set rasax.initialUser.username=$(RASAX_INITIALUSER_USERNAME) \
		--set rasax.initialUser.password=$(RASAX_INITIALUSER_PASSWORD) \
		--set rasax.passwordSalt=$(RASAX_PASSWORDSALT) \
		--set rasax.token=$(RASAX_TOKEN) \
		--set rasax.jwtSecret=$(RASAX_JWTSECRET) \
		--set rasa.tag=$(RASA_TAG) \
		--set rasa.token=$(RASA_TOKEN) \
		--set rabbitmq.rabbitmq.password=$(RABBITMQ_RABBITMQ_PASSWORD) \
		--set global.postgresql.postgresqlPassword=$(GLOBAL_POSTGRESQL_POSTGRESQLPASSWORD) \
		--set global.redis.password=$(GLOBAL_REDIS_PASSWORD) \
		--set app.name=$(APP_NAME) \
		--set app.tag=$(APP_TAG) \
		rasa-x/rasa-x
	
	@echo $(NEWLINE)	
	@echo Waiting until all deployments are AVAILABLE
	kubectl --namespace $(AWS_EKS_NAMESPACE) \
		wait \
		--for=condition=available \
		--timeout=20m \
		--all \
		deployment

rasa-enterprise-uninstall:
	@echo Uninstalling Rasa Enterprise release $(AWS_EKS_RELEASE_NAME).
	@echo $(NEWLINE)
	@helm --namespace $(AWS_EKS_NAMESPACE) \
		uninstall $(AWS_EKS_RELEASE_NAME)
	
rasa-enterprise-get-pods:
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		get pods
	
rasa-enterprise-get-secrets-postgresql:
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		get secret $(AWS_EKS_RELEASE_NAME)-postgresql -o yaml | \
		awk -F ': ' '/password/{print $2}' | base64 -d
		
rasa-enterprise-get-secrets-redis:
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		get secret $(AWS_EKS_RELEASE_NAME)-redis -o yaml | \
		awk -F ': ' '/password/{print $2}' | base64 -d
		
rasa-enterprise-get-secrets-rabbit:
	@kubectl --namespace $(AWS_EKS_NAMESPACE) \
		get secret $(AWS_EKS_RELEASE_NAME)-rabbit -o yaml | \
		awk -F ': ' '/password/{print $2}' | base64 -d