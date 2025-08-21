#!/bin/bash

#Run the following ONE-TIME-SCRIPT which creates and provisions the necessary GCP cloud services that will be required to create the DevSecOps CICD pipeline for a sample docker application. Here's all the service deployments that will occur once the script finishes:


#Enable the following GCP APIs
#Cloud Build, Binary Authorization, On-Demand Scanning, Resource Manager API, Artifact Registry API, Artifact Registry Vulnerability Scanning, Cloud Deploy API, KMS API and Cloud Functions.
gcloud services enable cloudbuild.googleapis.com
gcloud services enable binaryauthorization.googleapis.com
gcloud services enable ondemandscanning.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable containerscanning.googleapis.com
gcloud services enable clouddeploy.googleapis.com
gcloud services enable cloudkms.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable websecurityscanner.googleapis.com

#GCP Project Variables
LOCATION=asia-south1
PROJECT_ID=cicd6789
PROJECT_NUMBER=533446542117
CLOUD_BUILD_SA_EMAIL="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
BINAUTHZ_SA_EMAIL="service-${PROJECT_NUMBER}@gcp-sa-binaryauthorization.iam.gserviceaccount.com"
APP_SPOT="${PROJECT_ID}@appspot.gserviceaccount.com"

#Create the following custom IAM role
gcloud iam roles create cicdblogrole --project=${PROJECT_ID} \
    --title="cicdblogrole" \
    --description="Custom Role for GCP CICD Blog" \
    --permissions="artifactregistry.repositories.create,container.clusters.get,binaryauthorization.attestors.get,binaryauthorization.attestors.list,binaryauthorization.policy.update,clouddeploy.deliveryPipelines.get,clouddeploy.releases.get,cloudkms.cryptoKeyVersions.useToSign,cloudkms.cryptoKeyVersions.viewPublicKey,containeranalysis.notes.attachOccurrence,containeranalysis.notes.create,containeranalysis.notes.listOccurrences,containeranalysis.notes.setIamPolicy,iam.serviceAccounts.actAs,ondemandscanning.operations.get,ondemandscanning.scans.analyzePackages,ondemandscanning.scans.listVulnerabilities,serviceusage.services.enable,storage.objects.get" \
    --stage=Beta

#Add the newly created custom role, and "Cloud Deploy Admin" to the Cloud Build Service Account
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${CLOUD_BUILD_SA_EMAIL}" \
    --role="projects/${PROJECT_ID}/roles/cicdblogrole"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${CLOUD_BUILD_SA_EMAIL}" \
    --role='roles/clouddeploy.admin'

# Grant the Cloud Build service account the Cloud KMS CryptoKey Signer/Verifier role.
# This role is required for signing attestations with the KMS key.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${APP_SPOT}" \
    --role='roles/cloudkms.signerVerifier'

# Container Analysis Admin 
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${APP_SPOT}" \
    --role='roles/containeranalysis.admin'


#Add the following: "Artifact Registry Reader", "Cloud Deploy Runner" and "Kubernetes Engine Admin" IAM Role to the Compute Engine Service Account
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" --role='roles/artifactregistry.reader'

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" --role='roles/clouddeploy.jobRunner'

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" --role='roles/container.admin'

# Web Security Scanner Service Account Variables
WSS_SA_NAME="web-security-scanner-sa"
WSS_SA_EMAIL="${WSS_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create a dedicated service account for Web Security Scanner
gcloud iam service-accounts create "${WSS_SA_NAME}" \
    --description="Service account for running Web Security Scanner" \
    --display-name="Web Security Scanner SA"

# Grant the Web Security Scanner Editor role to the new service account
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${WSS_SA_EMAIL}" \
    --role="roles/websecurityscanner.editor"

#Create a Default VPC and its embedded Subnet. This is under the assumption that the new GCP project did NOT automatically create a default VPC and Subnet.
#If the creation of a default VPC is not needed, comment out the following 3 commands.

#SUBNET_RANGE=10.128.0.0/20
#gcloud compute networks create default --subnet-mode=custom --bgp-routing-mode=regional --mtu=1460
#gcloud compute networks subnets create default --project=$PROJECT_ID --range=$SUBNET_RANGE --network=default --region=$LOCATION

#Binary Authorization Attestor variables
ATTESTOR_ID=cb-attestor
NOTE_ID=cb-attestor-note

#KMS variables
KEY_LOCATION=global
KEYRING=blog-keyring
KEY_NAME=cd-blog
KEY_VERSION=1

curl "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=${NOTE_ID}" \
  --request "POST" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --header "X-Goog-User-Project: ${PROJECT_ID}" \
  --data-binary @- <<EOF
    {
      "name": "projects/${PROJECT_ID}/notes/${NOTE-ID}",
      "attestation": {
        "hint": {
          "human_readable_name": "Attestor Note is Created, Requires the creation of an attestor"
        }
      }
    }
EOF

#Create attestor and attach to the Container Analysis Note created in the step above
gcloud container binauthz attestors create $ATTESTOR_ID \
    --attestation-authority-note=$NOTE_ID \
    --attestation-authority-note-project=${PROJECT_ID}

#Before you can use this attestor, you must grant Binary Authorization the appropriate permissions to view the Container Analysis Note you created.
#Make a curl request to grant the necessary IAM role

curl "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/${NOTE_ID}:setIamPolicy" \
  --request "POST" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --header "x-goog-user-project: ${PROJECT_ID}" \
  --data-binary @- <<EOF
    {
      'resource': 'projects/${PROJECT_ID}/notes/${NOTE_ID}',
      'policy': {
        'bindings': [
          {
          'role': 'roles/containeranalysis.notes.occurrences.viewer',
          'members': [
            'serviceAccount:${BINAUTHZ_SA_EMAIL}'
            ]
          }
        ]
      }
    } 
EOF

#Before you can use this attestor, your authority needs to create a cryptographic key pair that can be used to sign container images.
#Create a keyring to hold a set of keys specific for Attestation
gcloud kms keyrings create "${KEYRING}" --location="${KEY_LOCATION}"

#Create a key name that will be assigned to the above key ring. 
gcloud kms keys create "${KEY_NAME}" \
    --keyring="${KEYRING}" \
    --location="${KEY_LOCATION}" --purpose asymmetric-signing \
    --default-algorithm="ec-sign-p256-sha256"

#Now, associate the key with your authority:
gcloud beta container binauthz attestors public-keys add  \
    --attestor="${ATTESTOR_ID}"  \
    --keyversion-project="${PROJECT_ID}"  \
    --keyversion-location="${KEY_LOCATION}" \
    --keyversion-keyring="${KEYRING}" \
    --keyversion-key="${KEY_NAME}" \
    --keyversion="${KEY_VERSION}"

#Validate the note is registered with attestor with KMS key
gcloud container binauthz attestors list

#Create Artifact Registry Repository where images will be stored
gcloud artifacts repositories create test-repo \
    --repository-format=Docker \
    --location=$LOCATION \
    --description="Artifact Registry for GCP DevSecOps CICD Blog" \
    --async

#This plugin is required for your kubectl command-line tool to authenticate with the GKE clusters.
gcloud components install gke-gcloud-auth-plugin

#Create three GKE clusters for test, staging and production. The Node.js docker image will be deployed as a release through the Cloud Deploy pipeline first in "dev". Next, the image deployment will be rolled to the "staging" cluster and once its successful, pending approval, the final image roll-out will deploy to the "prod" cluster.
#NOTE: If you're using a different VPC, ensure you change the --subnetwork config value to match against your VPC subnet

#GKE Cluster for Test environment, uncomment --subnetwork if you want to use a non-default VPC
gcloud container clusters create test \
    --project=$PROJECT_ID \
    --machine-type=e2-medium \
    --region $LOCATION \
    --num-nodes=1 \
    --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE \
    --labels=app=vulnapp-test \
    --subnetwork=default \
    --disk-size=20
 
STATIC_IP=$(gcloud compute addresses create ingress-ip --region=$LOCATION --project=$PROJECT_ID --format='value(address)')

#GKE Cluster for Staging environment
gcloud container clusters create staging \
    --project=$PROJECT_ID \
    --machine-type=e2-medium \
    --region $LOCATION \
    --num-nodes=1 \
    --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE \
    --labels=app=vulnapp-staging \
    --subnetwork=default \
    --disk-size=20

#GKE Cluster for Production environment
gcloud container clusters create prod \
    --project=$PROJECT_ID \
    --machine-type=e2-medium \
    --region $LOCATION \
    --num-nodes=1 \
    --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE \
    --labels=app=vulnapp-prod \
    --subnetwork=default \
    --disk-size=20

#Create cloud deploy pipeline
gcloud deploy apply --file clouddeploy.yaml --region=$LOCATION --project=$PROJECT_ID

# Install NGINX Ingress Controller on the 'test' cluster
gcloud container clusters get-credentials test --region $LOCATION --project $PROJECT_ID

# Display the static IP address on the screen
echo "The static IP address created is: $STATIC_IP"

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.loadBalancerIP=$STATIC_IP

# Install NGINX Ingress Controller on the 'staging' cluster
gcloud container clusters get-credentials staging --region $LOCATION --project $PROJECT_ID

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace

# Install NGINX Ingress Controller on the 'prod' cluster
gcloud container clusters get-credentials prod --region $LOCATION --project $PROJECT_ID

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace

