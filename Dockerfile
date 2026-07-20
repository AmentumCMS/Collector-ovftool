# Use Red Hat Universal Base Image 8
ARG UBIVER=9
ARG GOVC_VER=v0.52.0
ARG BUILD_IMAGE=registry1.dso.mil/ironbank/redhat/ubi/ubi${UBIVER}
ARG BASE_IMAGE=registry1.dso.mil/ironbank/redhat/ubi/ubi${UBIVER}-minimal

FROM ${BUILD_IMAGE} AS builder

ARG UBIVER
ARG GOVC_VER
ENV GOVC_VERSION=${GOVC_VER}

LABEL maintainer="Amentum CMS NISSC2" \
      description="Containerized OVF export tool with govc and ovftool on UBI"

# Install builder dependencies
RUN dnf update -y &&\
    dnf install -y \
    jq unzip tar findutils && \
    dnf clean all

# Install govc into a staging path
RUN mkdir -p /staging/usr/local/bin && \
    curl -sL "https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_x86_64.tar.gz" \
    | tar -xzvC /staging/usr/local/bin/ && chmod +x /staging/usr/local/bin/govc

# Download and install the latest OVF Tool into a staging path
COPY scripts/get_ovftool_latest.sh /usr/local/bin/get_ovftool_latest.sh
RUN chmod +x /usr/local/bin/get_ovftool_latest.sh && \
    OVFTOOL_INSTALL_DIR=/staging/opt /usr/local/bin/get_ovftool_latest.sh && \
    rm -rf /tmp/ovftool-download

FROM ${BASE_IMAGE} AS runtime

ARG UBIVER
ARG GOVC_VER
ENV GOVC_VERSION=${GOVC_VER}

LABEL maintainer="Amentum CMS NISSC2" \
      description="Containerized OVF export tool with govc and ovftool on UBI"

# Install runtime dependencies only
RUN microdnf install -y \
    libnsl2 glibc-langpack-en libxcrypt-compat \
    && microdnf clean all

RUN cd /usr/lib64 &&\
    ln -vs libnsl.so.3 libnsl.so &&\
    ln -vs libnsl.so.3 libnsl.so.1 &&\
    ln -vs libnsl.so.3 libnsl.so.2

COPY --from=builder /staging/usr/local/bin/govc /usr/local/bin/govc
COPY --from=builder /staging/opt/ovftool /opt/ovftool

ENV PATH="/opt/ovftool:$PATH"

# Optional: working directory
WORKDIR /workspace

# Check that stuff runs
RUN echo -e "Opt Listing:\n$(ls -Alht /opt/*)\n" &&\
    govc version &&\
    ovftool --version || exit 1

# Default entrypoint
ENTRYPOINT ["/bin/bash"]
