#!/bin/bash
set -o pipefail
source ./config/env.config

TANZU_CLI_REPO="https://github.com/vmware-tanzu/tanzu-cli"
CONTOUR_PKG_NAME="supsvc-contour"
HARBOR_PKG_NAME="supsvc-harbor"

if ! command -v curl >/dev/null 2>&1 ; then
	echo "curl missing. Please install curl."
	exit 1
fi

if ! command -v wget >/dev/null 2>&1 ; then
	echo "wget missing. Please install wget."
	exit 1
fi

if ! command -v tanzu >/dev/null 2>&1 ; then
  echo "Tanzu CLI missing. Please install Tanzu CLI (https://github.com/vmware-tanzu/tanzu-cli)."
  exit 1
else
    if ! tanzu imgpkg --help > /dev/null 2>&1 ; then
        echo "Installing Tanzu vSphere required plugins"
        if ! tanzu plugin install  --target k8s --group vmware-vsphere/default:v8.0.3 ; then
           v=$(tanzu version | \grep version | \sed -e 's/version: //')
           echo "Update the Tanzu CLI ($v) to the latest version (see $TANZU_CLI_REPO)."
           exit 1
        fi
    fi
fi

#if ! command -v imgpkg >/dev/null 2>&1 ; then
#  echo "imgpkg missing. Please install imgpkg CLI first."
#  exit 1
#fi

if ! command -v yq >/dev/null 2>&1 ; then
  echo "yq missing. Please install yq CLI version 4.x from https://github.com/mikefarah/yq/releases"
  exit 1
else
    if ! yq -P > /dev/null 2>&1 ; then 
        echo "yq version 4.x required. Please install yq version 4.x from https://github.com/mikefarah/yq/releases."
        exit 1
    fi
fi

# Create the download directory if it doesn't exist
mkdir -p "$DOWNLOAD_DIR_YML"
mkdir -p "$DOWNLOAD_DIR_TAR"
mkdir -p "$DOWNLOAD_DIR_BIN"

# Downloading Tanzu CLI, Tanzu vmware-vsphere plugin bundle and Tanzu Standard Packages
# Note: Commands will only work for Ubuntu/Linux, not MacOS or Windows.

echo "Downloading Tanzu CLI, Tanzu Packages and Tanzu CLI plugins..."
wget -q -O "$DOWNLOAD_DIR_BIN"/tanzu-cli-linux-amd64.tar.gz $$TANZU_CLI_REPO/releases/download/v1.1.0/tanzu-cli-linux-amd64.tar.gz
# tanzu plugin download-bundle --group vmware-vsphere/default:v8.0.3 --to-tar "$DOWNLOAD_DIR_BIN"/vmware-vsphere-plugin.tar.gz
tar -czvf "$DOWNLOAD_DIR_BIN"/tanzu-cli-plugins.tar.gz -C ~/.local/share/tanzu-cli .
tanzu imgpkg copy -b projects.registry.vmware.com/tkg/packages/standard/repo:"$TANZU_STANDARD_REPO_VERSION" --to-tar "$DOWNLOAD_DIR_BIN"/tanzu-packages.tar

# Download the package.yaml files for all the Supervisor Services. Modify as needed.
echo "Downloading all Supervisor Services configuration files..."
wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-tkgsvc.yaml          'https://packages.broadcom.com/artifactory/vsphere-distro/vsphere/iaas/kubernetes-service/3.2.0-package.yaml'
wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-lci.yaml             'https://vmwaresaas.jfrog.io/artifactory/supervisor-services/cci-supervisor-service/v1.0.2/cci-supervisor-service.yml'
wget -q -O "$DOWNLOAD_DIR_YML"/$HARBOR_PKG_NAME.yaml          'https://vmwaresaas.jfrog.io/ui/api/v1/download?repoKey=supervisor-services&path=harbor/v2.9.1/harbor.yml'
wget -q -O "$DOWNLOAD_DIR_YML"/$CONTOUR_PKG_NAME.yaml         'https://vmwaresaas.jfrog.io/ui/api/v1/download?repoKey=supervisor-services&path=contour/v1.28.2/contour.yml'
wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-externaldns.yaml     'https://vmwaresaas.jfrog.io/ui/api/v1/download?repoKey=supervisor-services&path=external-dns/v0.13.4/external-dns.yml'
wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-nsxmgmt.yaml         'https://vmwaresaas.jfrog.io/ui/api/v1/download?repoKey=supervisor-services&path=nsx-management-proxy/v0.2.1/nsx-management-proxy.yml'
wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-argocd-operator.yaml 'https://raw.githubusercontent.com/vsphere-tmm/Supervisor-Services/refs/heads/main/supervisor-services-labs/argocd-operator/v0.12.0/argocd-operator.yaml'
#wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-dsm-operator.yaml    'https://packages.broadcom.com/artifactory/dsm-distro/dsm-consumption-operator/supervisor-service/1.2.0/package.yaml'
#wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-minio.yaml           'https://projects.packages.broadcom.com/artifactory/vsphere-distro/vsphere/iaas/minio/minio-service-definition-v2.0.10-3.yaml'
#wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-cloudian.yaml        'https://vmwaresaas.jfrog.io/ui/api/v1/download?repoKey=vDPP-Partner-YAML&path=Cloudian%252FHyperstore%252FSupervisorService%252F1.3.1%252Fhyperstore-supervisorservice-1.3.1.yaml'
#wget -q -O "$DOWNLOAD_DIR_YML"/supsvc-velero-operator.yaml 'https://vmwaresaas.jfrog.io/ui/api/v1/download?repoKey=Velero-YAML&path=Velero%252FSupervisorService%252F1.6.1%252Fvelero-vsphere-1.6.1-def.yaml'

echo
echo "Downloading Supervisor Services images using imgpkg..."
echo

for file in "$DOWNLOAD_DIR_YML"/*.yaml; do
    full_filename=$(basename "$file")
    file_name="${full_filename%.yaml}"   
    image=$(yq -P '(.|select(.kind == "Package").spec.template.spec.fetch[].imgpkgBundle.image)' "$file")

    if [ "$image" ]
    then
        echo Now downloading "$image"...
        tanzu imgpkg copy -b "$image" --to-tar "$DOWNLOAD_DIR_TAR"/"$file_name".tar --cosign-signatures

        # Get the name of the image from the package.spec.template.spec.fetch[].imgpkgBundle.image 
        # and replace the URL with the new harbor location
        if [ "$file_name" == "$CONTOUR_PKG_NAME" ] || [ "$file_name" == "$HARBOR_PKG_NAME" ]
        then
            # Will fetch images from the bootstrap container registry
            newurl="$BOOTSTRAP_REGISTRY"/"${BOOTSTRAP_SUPSVC_REPO}"/"${image##*/}"
        else
            newurl="$PLATFORM_REGISTRY"/"${PLATFORM_SUPSVC_REPO}"/"${image##*/}"
        fi
        echo Updating Supervisor Service config file image to "$newurl"...
        a=$newurl yq -P '(.|select(.kind == "Package").spec.template.spec.fetch[].imgpkgBundle.image = env(a))' -i "$file"
    fi
done
