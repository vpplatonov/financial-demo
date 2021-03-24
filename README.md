# Notes on Rasa `2.x / 1.x`

1. The master branch of this repo is compatible with Rasa Open Source **version 2.x**
2. The bot for **Rasa 1.x** can be found in the [rasa-1 branch](https://github.com/RasaHQ/financial-demo/tree/rasa-1).



# Financial Services Example Bot

This is an example chatbot demonstrating how to build AI assistants for financial services and banking. This starter pack can be used as a base for your own development or as a reference guide for implementing common banking-industry features with Rasa. It includes pre-built intents, actions, and stories for handling conversation flows like checking spending history and transferring money to another account.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Financial Services Example Bot](#financial-services-example-bot)
  - [Install dependencies](#install-dependencies)
  - [Run the bot](#run-the-bot)
  - [Overview of the files](#overview-of-the-files)
  - [Things you can ask the bot](#things-you-can-ask-the-bot)
  - [Handoff](#handoff)
    - [Try it out](#try-it-out)
    - [How it works](#how-it-works)
    - [Bot-side configuration](#bot-side-configuration)
  - [Testing the bot](#testing-the-bot)
  - [Rasa X Deployment](#rasa-x-deployment)
  - [Action Server Image](#action-server-image)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Install dependencies

Run:
```bash
pip install -r requirements.txt
```

To install development dependencies:

```bash
pip install -r requirements-dev.txt
pre-commit install
python -m spacy download en_core_web_md en
python -m spacy link en_core_web_md en
```

> With pre-commit installed, the `black` and `doctoc` hooks will run on every `git commit`.
> If any changes are made by the hooks, you will need to re-add changed files and re-commit your changes.

## Run the bot

Use `rasa train` to train a model.

Then, to run, first set up your action server in one terminal window, listening on port 5056:
```bash
rasa run actions --port 5056
```

Note that port 5056 is used for the action server, to avoid a conflict when you also run the helpdesk bot as described below in the `handoff` section.

In another window, run the duckling server (for entity extraction):

```bash
docker run -p 8000:8000 rasa/duckling
```

Then to talk to the bot, run:
```
rasa shell --debug
```

Note that `--debug` mode will produce a lot of output meant to help you understand how the bot is working
under the hood. To simply talk to the bot, you can remove this flag.


You can also try out your bot locally using Rasa X by running
```
rasa x
```

Refer to our guided workflow in the [Wiki page](https://github.com/RasaHQ/financial-demo/wiki/Using-Rasa-X-with-the-Financial-Demo) for how to get started with Rasa X in local mode.


## Overview of the files

`data/nlu/nlu.yml` - contains NLU training data

`data/nlu/rules.yml` - contains rules training data

`data/stories/stories*.yml` - contains stories training data

`actions.py` - contains custom action/api code

`domain.yml` - the domain file, including bot response templates

`config.yml` - training configurations for the NLU pipeline and policy ensemble

`tests/` - end-to-end tests


## Things you can ask the bot

The bot currently has five skills. You can ask it to:
1. Transfer money to another person
2. Check your earning or spending history (with a specific vendor or overall)
3. Answer a question about transfer charges
4. Pay a credit card bill
5. Tell you your account balance

It also has a limited ability to switch skills mid-transaction and then return to the transaction at hand.

For the purposes of illustration, the bot recognises the following fictional credit card accounts:

- `emblem`
- `justice bank`
- `credit all`
- `iron bank`

It recognises the following payment amounts (besides actual currency amounts):

- `minimum balance`
- `current balance`

It recognises the following vendors (for spending history):

- `Starbucks`
- `Amazon`
- `Target`

You can change any of these by modifying `actions.py` and the corresponding NLU data.

If configured, the bot can also hand off to another bot in response to the user asking for handoff. More [details on handoff](#handoff) below.

## Handoff

This bot includes a simple skill for handing off the conversation to another bot or a human.
This demo relies on [this fork of chatroom](https://github.com/RasaHQ/chatroom) to work, however you
could implement similar behaviour in another channel and then use that instead. See the chatroom README for
more details on channel-side configuration.


Using the default set up, the handoff skill enables this kind of conversation with two bots:

<img src="./handoff.gif" width="200">


### Try it out

The simplest way to use the handoff feature is to do the following:

1. Clone [chatroom](https://github.com/RasaHQ/chatroom) and [Helpdesk-Assistant](https://github.com/RasaHQ/helpdesk-assistant) alongside this repo
2. In the chatroom repo, install the dependencies:
```bash
yarn install
```
3. In the chatroom repo, build and serve chatroom:
```bash
yarn build
yarn serve
```
4. In the Helpdesk-Assistant repo, install the dependencies and train a model (see the Helpdesk-Assistant README)
5. In the Helpdesk-Assistant repo, run the rasa server and action server at the default ports (shown here for clarity)
   In one terminal window:
    ```bash
    rasa run --enable-api --cors "*" --port 5005 --debug
    ```
    In another terminal window:
    ```bash
    rasa run actions --port 5055 --debug
    ```
6. In the Financial-Demo repo (i.e. this repo), run the rasa server and action server at **the non-default ports shown below**
   In one terminal window:
    ```bash
    rasa run --enable-api --cors "*" --port 5006 --debug
    ```
    In another terminal window:
    ```bash
    rasa run actions --port 5056 --debug
    ```
7. Open `chatroom_handoff.html` in a browser to see handoff in action


### How it works

Using chatroom, the general approach is as follows:

1. User asks original bot for a handoff.
2. The original bot handles the request and eventually
   sends a message with the following custom json payload:
    ```
        {
            "handoff_host": "<url of handoff host endpoint>",
            "title": "<title for bot/channel handed off to>"
            }
    ```
    This message is not displayed in the Chatroom window.
3. Chatroom switches the host to the specified `handoff_host`
4. The original bot no longer receives any messages.
5. The handoff host receives the message `/handoff{"from_host":"<original bot url">}`
6. The handoff host should be configured to respond to this message with something like,
   "Hi, I'm <so and so>, how can I help you??"
7. The handoff host can send a message in the same format as specified above to hand back to the original bot.
   In this case the same pattern repeats, but with
   the roles reversed. It could also hand off to yet another bot/human.

### Bot-side configuration

The "try it out" section doesn't require any further configuration; this section is for those
who want to change or further understand the set up.

For this demo, the user can ask for a human, but they'll be offered a bot (or bots) instead,
so that the conversation looks like this:


For handoff to work, you need at least one "handoff_host". You can specify any number of handoff hosts in the file `actions/handoff_config.yml`.
```
handoff_hosts:
    helpdesk_assistant:
      title: "Helpdesk Assistant"
      url: "http://localhost:5005"
    ## you can add more handoff hosts to this list e.g.
    # moodbot:
    #   title: "MoodBot"
    #   url: "http://localhost:5007"
```

Handoff hosts can be other locally running rasa bots, or anything that serves responses in the format that chatroom
accepts. If a handoff host is not a rasa bot, you will of course want to update the response text to tell the user
who/what they are being handed off to.

The [Helpdesk-Assistant](https://github.com/RasaHQ/helpdesk-assistant) bot has been set up to handle handoff in exactly the same way as Helpdesk-Assistant,
so the simplest way to see handoff in action is to clone Financial-Demo alongside this repo.

If you list other locally running bots as handoff hosts, make sure the ports on which the various rasa servers & action servers are running do not conflict with each other.


## Testing the bot

You can test the bot on the test conversations by:

- start duckling
- running  `rasa test`.

This will run [end-to-end testing](https://rasa.com/docs/rasa/user-guide/testing-your-assistant/#end-to-end-testing) on the conversations in `tests/test_stories.yml`.

All tests must pass.



## Rasa X Deployment

To [deploy financial-demo](https://rasa.com/docs/rasa/user-guide/how-to-deploy/), it is highly recommended to make use of the [one line deploy script](https://rasa.com/docs/rasa-x/installation-and-setup/one-line-deploy-script/) for Rasa X. 

As part of the deployment, you'll need to set up [git integration](https://rasa.com/docs/rasa-x/installation-and-setup/integrated-version-control/#connect-your-rasa-x-server-to-a-git-repository) to pull in your data and configurations, and build or pull an action server image.


## Action Server Image

You will need to have docker installed in order to build the action server image. If you haven't made any changes to the action code, you can also use the [public image on Dockerhub](https://hub.docker.com/r/rasa/financial-demo) instead of building it yourself.

Build & tag the image:

```bash
export ACTION_SERVER_DOCKERPATH=<dockerID>/<name-of-image>:<tag-of-image>
make docker-build
```

Run the action server container:

```bash
make docker-run
```

Perform a smoke test on the health endpoint:

```bash
make docker-test
```

Once you have confirmed that the container works as it should, push the container image to a registry:

```bash
# login to a container registry with your credentials
docker login  

# check the registry logged into
docker system info | grep Registry

# push the action server image
make docker-push
```

## CI/CD

Tips on creating a [CI/CD pipeline](https://rasa.com/docs/rasa/user-guide/setting-up-ci-cd) for Rasa.

### AWS

#### Preparation

The CI/CD pipeline of financial-demo uses AWS.

After cloning or forking the financial-demo GitHub repository you must set up the following items before the pipeline can run.

##### IAM User API Keys

The CI/CD pipeline uses the [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html#cliv2-linux-install).

The [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html#cliv2-linux-install) needs a set of IAM User API keys for authentication & authorization:

- In your AWS Console, go to IAM dashboard to create a new set of API keys:

  - Click on Users

  - Click on Add user

    - User name = findemo  *(The actual name is not important, we will never use this name directly)*

      Choose "**programmatic access**." This allows you to use the aws cli to interact with AWS.

    - Click on Next: Permissions

      - Click on *Attach existing policies directly*

        For IAM access, you can choose “**AdministratorAccess**”, or limit access to only what is needed by the CD pipeline.

    - Click on Next: Tags

    - Click on Next: Review

    - Click on Create user

    - Store in a safe location: `Access key ID` & `Secret access key`

- In your Github repository, go to `Settings > Secrets`, and add two `New repository secrets` :

  - AWS_ACCESS_KEY_ID = `Access key ID`
  - AWS_SECRET_ACCESS_KEY = `Secret access key` 

  This allows the GitHub actions to configure the aws cli.

##### SSH Key Pair

To be able to run `ansible` commands on an EC2 over SSH, you need an SSH Key Pair

- In your AWS Console, create a Key Pair with the name `findemo`, and download the file `findemo.pem` which contains a public SSH key. *Note that the name `findemo` is important, since it is used by the CloudFormation template.*
- TODO...add the `findemo.pem` (..get a fingerprint?) to GitHub, so the github actions can run ansible which uses SSH to run commands on the EC2 instance.

##### AWS Elastic Container Registry (ECR)

The CI/CD pipeline pushes the action server docker image to an ECR repository.

Using the AWS ECR Console, create a private container registry, for example with name `financial-demo`.

Update this section in the `CI/CD.yml` file:

```yaml
env:
  AWS_REGION: us-west-2
  AWS_ECR_URI: 024629701212.dkr.ecr.us-west-2.amazonaws.com
  AWS_ECR_REPOSITORY: financial-demo
```

##### AWS S3 Bucket

The CI/CD pipeline uploads the trained model to an S3 bucket.

In the same AWS region as for the ECR, create an S3 bucket with a globally unique name. 

You can do this in the AWS S3 Console, or by running this command

```bash
make aws-s3-create AWS_REGION=<...> AWS_S3_NAME=<...>
```

Then, update this section in the `CI/CD.yml`:

```yaml
env:
  AWS_REGION: us-west-2
  AWS_S3_NAME: rasa-financial-demo
```



#### Run the CI/CD pipeline manually

The CI/CD steps are automatically run by the GitHub actions when you push changes but you can also run many steps manually from your local computer. This can help with bootstrapping & debugging.

##### Preparation

###### Install AWS CLI v2

See the [installation instructions](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html).

Check it works:

```bash
aws --version
```

###### Configure your AWS CLI

```bash
aws configure
AWS Access Key ID [None]: -----          # See above: IAM User API Keys
AWS Secret Access Key [None]: -------    # See above: IAM User API Keys
Default region name [None]: us-west-2    # The CD pipeline uses us-west-2 
Default output format [None]: 

# verify it works
aws s3 ls
```

##### job: action_server

```bash
# Test the python code
pip install -r requirements-dev.txt
make lint
make types
make test

# Build, run & test the action server docker image
make docker-build
make docker-run
make docker-test

# Login & push the action server docker image
make aws-docker-login
make docker-push
```

Notes:

- The CI/CD pipeline uses a GitHub action r[asa-action-server-gha](https://github.com/RasaHQ/rasa-action-server-gha) with a default `Dockerfile`.
- The command `make docker-build` is provided for local development purposes only. It uses the `Dockerfile` of the repository and has debug turned on. 

##### job: rasa_model

```bash
# Train the model
make rasa-train

# Start duckling server & Test the model
docker run -p 8000:8000 rasa/duckling
make rasa-test

# Upload the model to S3
make aws-s3-copy-rasa-model
```

Notes:

- The CI/CD pipeline uses a GitHub action [rasa-train-test-gha](https://github.com/RasaHQ/rasa-train-test-gha).
- The commands `make rasa-train` & `make rasa-test` are provided for local development purposes only. 

##### 

