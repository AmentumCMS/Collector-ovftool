# Use Red Hat Universal Base Image 8
ARG UBIVER=9
ARG GOVC_VER=v0.52.0
FROM registry1.dso.mil/ironbank/redhat/ubi/ubi${UBIVER}-minimal

ARG UBIVER
ARG GOVC_VER
ENV GOVC_VERSION=${GOVC_VER}

LABEL maintainer="Amentum CMS NISSC2" \
      description="Containerized OVF export tool with govc and ovftool on UBI"

# Install required packages
RUN microdnf install -y \
    jq unzip tar pigz gzip \
    libnsl2 glibc-langpack-en libxcrypt-compat \
    && microdnf clean all

RUN cd /usr/lib64 &&\
    ln -vs libnsl.so.3 libnsl.so &&\
    ln -vs libnsl.so.3 libnsl.so.1 &&\
    ln -vs libnsl.so.3 libnsl.so.2

# Install govc
# RUN microdnf -y install https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govmomi_${GOVC_VERSION}_linux_amd64.rpm

# Install govc
RUN curl -sL "https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_x86_64.tar.gz" \
    | tar -xzvC /usr/local/bin/ && chmod +x /usr/local/bin/govc

# Add ovftool (must be manually downloaded and placed in build context)
ADD ./binaries/VMware-ovftool-5.0.0-24781994-lin.x86_64.tgz /opt/
ENV PATH="/opt/ovftool:$PATH"

# Optional: working directory
WORKDIR /workspace

# Check that stuff runs
RUN echo -e "Opt Listing:\n$(ls -1Ssh /opt/*)\n" &&\
    govc version &&\
    /opt/ovftool/ovftool --version || exit 1

# Default entrypoint
ENTRYPOINT ["/bin/bash"]
