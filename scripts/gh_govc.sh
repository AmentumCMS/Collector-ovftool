#!/bin/bash
SRC=$(basename "$PWD")
REPO="vmware/govmomi"
DEST="../binaries/govc"

echo -e "\nWorking with github repo $REPO"
echo -e "Listing releases\n"
gh release list -R $REPO
echo -e "\nDownloading Latest to $DEST\n"
gh release download \
  -p "*Windows_x86_64*" \
  -p "*amd*.rpm" \
  -p "*Linux*x86_64*" \
  -p "checksums.txt" \
  -D $DEST -R $REPO
ls -Alht $DEST 
if [ $? ];then
  echo -e "\nDownload Complete!"
else
  echo "ERROR!"
fi