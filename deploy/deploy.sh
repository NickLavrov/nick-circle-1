#!/bin/bash
set -e

SERVICE=$1
ENVIRONMENT=$2
PROJECT_PATH=$3
SERVICE_PATH=$4
DOCKERFILE_PATH=$5

GIT_COMMIT_SHA=$(git rev-parse HEAD)
DEPLOY_SCRIPT_TIMESTAMP=$(date +"%s")
TAG=$GIT_COMMIT_SHA.$DEPLOY_SCRIPT_TIMESTAMP
ENVIRONMENT_NAME=nick-circle-1-$ENVIRONMENT
SERVICE_ROOT=$PROJECT_PATH/$SERVICE_PATH
DOCKERFILE=$SERVICE_ROOT/$DOCKERFILE_PATH
SERVICE_NAME=nick-circle-1-$SERVICE
SERVICE_TAG=$SERVICE_NAME:$TAG
SECRET_NAME=nick-circle-1-$SERVICE-secrets
CONFIGMAP_NAME=nick-circle-1-$SERVICE-configmap
DEPLOY_PATH=$PROJECT_PATH/deploy

# define login functions

function gigster_network_login() {
    GCP_PROJECT_ID=${GCP_PROJECT_ID:-gdedev-nick-circle-1}
    GCP_ACCOUNT_ID=${GCP_ACCOUNT_ID:-$(gcloud config get-value account)}
    echo "Deploying with google account $GCP_ACCOUNT_ID"
    if [[ ! "$GCP_ACCOUNT_ID" =~ ^[a-zA-Z0-9\.-]+@gigsternetwork.com$ ]]; then
      echo "WARNING: $GCP_ACCOUNT_ID is not allowed to deploy. Sign in using a gigsternetwork google account: \`gcloud auth login <account>@gigsternetwork.com\`";
    fi
    SERVICE_IMAGE=gcr.io/$GCP_PROJECT_ID/$SERVICE_TAG
    KUBE_CONTEXT=${KUBE_CONTEXT:-gke_gde-core-dev_us-east1-c_gde-core-dev}

    gcloud auth configure-docker --project $GCP_PROJECT_ID
}

if [[ "$ENVIRONMENT" = "prod" ]]; then
  gigster_network_login
  PROVIDER_NAME=gigster-network
  PROVIDER_KIND=gcp
fi
if [[ "$ENVIRONMENT" = "staging" ]]; then
  gigster_network_login
  PROVIDER_NAME=gigster-network
  PROVIDER_KIND=gcp
fi
# build the docker image
docker build -f $DOCKERFILE -t $SERVICE_TAG $SERVICE_ROOT
docker tag $SERVICE_TAG $SERVICE_IMAGE
docker push $SERVICE_IMAGE

# create the configmap
kubectl delete configmap $CONFIGMAP_NAME -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT || echo \
  "Failed to delete deployment configmap. OK for first time deployment."
touch $DEPLOY_PATH/$ENVIRONMENT_NAME/.config
kubectl create configmap $CONFIGMAP_NAME --from-env-file=$DEPLOY_PATH/$ENVIRONMENT_NAME/.config -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT

# create the secrets
kubectl delete secret $SECRET_NAME -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT || echo \
  "Failed to delete deployment secrets. OK for first time deployment."
touch $DEPLOY_PATH/$ENVIRONMENT_NAME/.env
kubectl create secret generic $SECRET_NAME --from-env-file=$DEPLOY_PATH/$ENVIRONMENT_NAME/.env -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT

# apply the manifests to the environment
cp $DEPLOY_PATH/$SERVICE_NAME-deployment.yaml $DEPLOY_PATH/$SERVICE_NAME-deployment-tmp.yaml
sed -i.bak "s|__IMAGE__|$SERVICE_IMAGE|" $DEPLOY_PATH/$SERVICE_NAME-deployment-tmp.yaml
rm $DEPLOY_PATH/$SERVICE_NAME-deployment-tmp.yaml.bak

kubectl apply -f $DEPLOY_PATH/$ENVIRONMENT_NAME/$SERVICE_NAME-service.yaml -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT
if [[ "$PROVIDER_KIND" = "gcp" ]]; then
  kubectl apply -f $DEPLOY_PATH/$ENVIRONMENT_NAME/$SERVICE_NAME-ingress.yaml -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT
fi
kubectl apply -f $DEPLOY_PATH/$SERVICE_NAME-deployment-tmp.yaml -n=$ENVIRONMENT_NAME --context $KUBE_CONTEXT

rm $DEPLOY_PATH/$SERVICE_NAME-deployment-tmp.yaml

echo "All Done! Visit https://$SERVICE_NAME-$ENVIRONMENT.$PROVIDER_KIND-dev.gigsternetwork.com to see your deployment live."
