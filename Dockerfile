# Only 2026b tested
ARG MATLAB_RELEASE=R2026b

# Source CUDA 11.8 toolkit from Nvidia's docker image for 22.04
FROM docker.io/nvidia/cuda:11.8.0-devel-ubuntu22.04 AS cuda

# MATLAB's system dependencies from MathWorks base image
# https://hub.docker.com/r/mathworks/matlab-deps
FROM docker.io/mathworks/matlab-deps:${MATLAB_RELEASE}-ubuntu22.04 AS base

ARG MATLAB_RELEASE
ARG MATLAB_PRODUCT_LIST="MATLAB"
ARG MATLAB_INSTALL_LOCATION="/opt/matlab"
ENV DEBIAN_FRONTEND=noninteractive

# MULTEM runtime/build libraries and mpm prerequisites
RUN apt-get update && apt-get install --no-install-recommends --yes \
        wget ca-certificates unzip \
        libfftw3-3 libfftw3-single3 libblas3 liblapack3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility
# No provision for graphics cap

# Matlab installation from official docker template for building matlab images
# https://github.com/mathworks-ref-arch/matlab-dockerfile/blob/main/Dockerfile
# Add "matlab" user and grant sudo permission
RUN adduser --shell /bin/bash --disabled-password --gecos "" matlab \
    && mkdir -p /home/matlab/Documents/MATLAB \
    && chown -R matlab:matlab /home/matlab \
    && echo "matlab ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/matlab \
    && chmod 0440 /etc/sudoers.d/matlab
USER matlab
WORKDIR /home/matlab

# Install MATLAB with mpm; pass $HOME to install support packages there
RUN wget -q https://www.mathworks.com/mpm/glnxa64/mpm \
    && chmod +x mpm \
    && sudo HOME=${HOME} ./mpm install \
        --release=${MATLAB_RELEASE} \
        --destination=${MATLAB_INSTALL_LOCATION} \
        --products ${MATLAB_PRODUCT_LIST} \
    || (echo "MPM Installation Failure. See below for more information:" \
        && cat /tmp/mathworks_root.log && false) \
    && sudo rm -rf mpm /tmp/mathworks_root.log \
    && sudo ln -s ${MATLAB_INSTALL_LOCATION}/bin/matlab /usr/local/bin/matlab

# Jul 25 multem release
RUN wget -q https://github.com/Ivanlh20/multem/releases/download/v2.2.8/multem.zip \
    && unzip -q multem.zip -d /tmp/multem-full \
    && mkdir -p /home/matlab/multem-release/mex_bin \
    && cp /tmp/multem-full/mex_bin/*.mexa64 /home/matlab/multem-release/mex_bin/ \
    && cp -r /tmp/multem-full/mex_examples_multem \
             /tmp/multem-full/matlab_functions \
             /tmp/multem-full/crystalline_materials \
             /home/matlab/multem-release/ \
    && rm -rf /tmp/multem-full multem.zip

WORKDIR /home/matlab/multem-release/mex_examples_multem

ENTRYPOINT ["matlab"]
CMD ["-licmode", "online"]

# Full image: complete CUDA 11.8 toolkit
FROM base AS full
USER root
COPY --from=cuda /usr/local/cuda-11.8 /usr/local/cuda-11.8
RUN echo /usr/local/cuda-11.8/lib64 > /etc/ld.so.conf.d/cuda-11-8.conf && ldconfig
ENV PATH=/usr/local/cuda-11.8/bin:$PATH
USER matlab

# Slim image: CUDA 11.8 - minimal libraries used by multem (half size)
FROM base AS slim
USER root
COPY --from=cuda /usr/local/cuda-11.8/lib64/libcudart.so.11* /usr/local/cuda-11.8/lib64/
COPY --from=cuda /usr/local/cuda-11.8/lib64/libcufft.so.10* /usr/local/cuda-11.8/lib64/
RUN echo /usr/local/cuda-11.8/lib64 > /etc/ld.so.conf.d/cuda-11-8.conf && ldconfig
USER matlab
