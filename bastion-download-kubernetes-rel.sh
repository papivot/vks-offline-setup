#!/bin/bash
set -o pipefail
source ./config/env.config

if ! command -v jq >/dev/null 2>&1 ; then
  echo "JQ not installed. Exiting...."
  exit 1
fi
if ! command -v wget >/dev/null 2>&1 ; then
  echo "wget not installed. Exiting...."
  exit 1
fi

# Create the download directory if it doesn't exist
mkdir -p "$DOWNLOAD_VKR_OVA"

echo
echo "The VMware subscribed content library has the following Kubernetes Release images:"
echo
curl -s https://wp-content.vmware.com/v2/latest/items.json |jq -r '.items[]| .created + "\t" + .name'|sort

echo
echo "The list shown above is sorted by release date (last one is the most recent) with the corresponding names of the"
echo "Kubernetes Release in the second column."
read -p "Enter the name of the Kubernetes Release OVA that you want to download and zip for offline upload: " tkgrimage

echo
echo "Downloading all files for the TKG image: ${tkgrimage} into $DOWNLOAD_VKR_OVA ..."
echo
wget -q --show-progress --no-parent -r -nH --cut-dirs=2 --reject="index.html*" -P $DOWNLOAD_VKR_OVA https://wp-content.vmware.com/v2/latest/"${tkgrimage}"/

echo "Compressing downloaded files..."
tar -cvzf "$DOWNLOAD_VKR_OVA/${tkgrimage}".tar.gz "$DOWNLOAD_VKR_OVA/${tkgrimage}"

echo
echo "Cleaning up..."
[ -d "$DOWNLOAD_VKR_OVA/${tkgrimage}" ] && rm -rf "$DOWNLOAD_VKR_OVA/${tkgrimage}/"

echo "Copy the file ${DOWNLOAD_VKR_OVA}/${tkgrimage}.tar.gz to the offline admin machine that has access to the vSphere environment."
echo "You can untar the file and upload the OVA files to a Content Library called \"Local\""
echo "Optionally, you can install and configure govc (https://github.com/vmware/govmomi/tree/main/govc) on the offline admin machine:"
echo "Use the following command on the admin machine to import the image to the vCenter Content Library called \"Local\":"
echo
echo "     tar -xzvf ${tkgrimage}.tar.gz"
echo "     cd ${tkgrimage}"
echo "     govc library.import -n ${tkgrimage} -m=true Local photon-ova.ovf"
echo "     or"
echo "     govc library.import -n ${tkgrimage} -m=true Local ubuntu-ova.ovf"