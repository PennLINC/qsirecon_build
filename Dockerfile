ARG TAG_FREESURFER
ARG TAG_ANTS
ARG TAG_MRTRIX3
ARG TAG_3TISSUE
ARG TAG_DSISTUDIO
ARG TAG_MICROMAMBA
ARG TAG_AFNI
ARG TAG_TORTOISE
ARG TAG_TORTOISECUDA

# COPY can't handle variables, so here we go
FROM pennlinc/qsirecon-micromamba:${TAG_MICROMAMBA} as build_micromamba
FROM pennbbl/qsiprep-freesurfer:${TAG_FREESURFER} as build_freesurfer
FROM pennbbl/qsiprep-ants:${TAG_ANTS} as build_ants
FROM pennbbl/qsiprep-mrtrix3:${TAG_MRTRIX3} as build_mrtrix3
FROM pennbbl/qsiprep-3tissue:${TAG_3TISSUE} as build_3tissue
FROM pennbbl/qsiprep-dsistudio:${TAG_DSISTUDIO} as build_dsistudio
FROM pennbbl/qsiprep-afni:${TAG_AFNI} as build_afni
FROM pennbbl/qsiprep-drbuddi:${TAG_TORTOISE} as build_tortoise
FROM pennbbl/qsiprep-drbuddicuda:${TAG_TORTOISE} as build_tortoisecuda
FROM pennlinc/atlaspack:0.1.0 as atlaspack
FROM nvidia/cuda:11.1.1-runtime-ubuntu18.04 as ubuntu

FROM ubuntu

## ANTs
COPY --from=build_ants /opt/ants /opt/ants
ENV ANTSPATH="/opt/ants/bin" \
    LD_LIBRARY_PATH="/opt/ants/lib:$LD_LIBRARY_PATH" \
    PATH="$PATH:/opt/ants/bin" \
    ANTS_DEPS="zlib1g-dev"

## DSI Studio
ENV QT_BASE_DIR="/opt/qt512"
ENV QTDIR="$QT_BASE_DIR" \
    LD_LIBRARY_PATH="$QT_BASE_DIR/lib/x86_64-linux-gnu:$QT_BASE_DIR/lib:$LD_LIBRARY_PATH" \
    PKG_CONFIG_PATH="$QT_BASE_DIR/lib/pkgconfig:$PKG_CONFIG_PATH" \
    PATH="$QT_BASE_DIR/bin:$PATH:/opt/dsi-studio" \
    DSI_STUDIO_DEPS="qt512base qt512charts-no-lgpl"

## MRtrix3
COPY --from=build_mrtrix3 /opt/mrtrix3-latest /opt/mrtrix3-latest
## MRtrix3-3Tissue
COPY --from=build_3tissue /opt/3Tissue /opt/3Tissue
ENV PATH="$PATH:/opt/mrtrix3-latest/bin:/opt/3Tissue/bin" \
    MRTRIX3_DEPS="bzip2 ca-certificates curl libpng16-16 libblas3 liblapack3"

## Freesurfer
COPY --from=build_freesurfer /opt/freesurfer /opt/freesurfer
# Simulate SetUpFreeSurfer.sh
ENV FSL_DIR="/opt/conda/envs/fslqsirecon" \
    OS="Linux" \
    FS_OVERRIDE=0 \
    FIX_VERTEX_AREA="" \
    FSF_OUTPUT_FORMAT="nii.gz" \
    FREESURFER_HOME="/opt/freesurfer"
ENV SUBJECTS_DIR="$FREESURFER_HOME/subjects" \
    FUNCTIONALS_DIR="$FREESURFER_HOME/sessions" \
    MNI_DIR="$FREESURFER_HOME/mni" \
    LOCAL_DIR="$FREESURFER_HOME/local" \
    MINC_BIN_DIR="$FREESURFER_HOME/mni/bin" \
    MINC_LIB_DIR="$FREESURFER_HOME/mni/lib" \
    MNI_DATAPATH="$FREESURFER_HOME/mni/data"
ENV PERL5LIB="$MINC_LIB_DIR/perl5/5.8.5" \
    MNI_PERL5LIB="$MINC_LIB_DIR/perl5/5.8.5" \
    PATH="$FREESURFER_HOME/bin:$FSFAST_HOME/bin:$FREESURFER_HOME/tktools:$MINC_BIN_DIR:$PATH" \
    FREESURFER_DEPS="bc ca-certificates curl libgomp1 libxmu6 libxt6 tcsh perl"
RUN chmod a+rx /opt/freesurfer/bin/mri_synthseg /opt/freesurfer/bin/mri_synthstrip

## AFNI
COPY --from=build_afni /opt/afni-latest /opt/afni-latest
ENV PATH="$PATH:/opt/afni-latest" \
    AFNI_INSTALLDIR=/opt/afni-latest \
    AFNI_IMSAVE_WARNINGS=NO

## TORTOISE
COPY --from=build_tortoise /src/TORTOISEV4/bin /src/TORTOISEV4/bin
COPY --from=build_tortoise /src/TORTOISEV4/settings /src/TORTOISEV4/settings
COPY --from=build_tortoise /usr/local/boost176 /usr/local/boost176
COPY --from=build_tortoisecuda /src/TORTOISEV4/bin/*cuda /src/TORTOISEV4/bin/
ENV PATH="$PATH:/src/TORTOISEV4/bin" \
    TORTOISE_DEPS="fftw3"

# Create a shared $HOME directory
RUN useradd -m -s /bin/bash -G users qsiprep
WORKDIR /home/qsiprep

## Python, compiled dependencies. The python files are in /opt/conda/envs/qsiprep
## because the original build does not care whether it's for qsiprep or qsirecon
COPY --from=build_micromamba /opt/conda/envs/qsiprep /opt/conda/envs/qsiprep
COPY --from=build_micromamba /home/qsiprep/.dipy /home/qsiprep/.dipy
ENV PATH="/opt/conda/envs/qsiprep/bin:$PATH"

RUN apt-get update -qq \
    && apt-get install -y -q --no-install-recommends \
           apt-utils \
           bzip2 \
           ca-certificates \
           curl \
           ed \
           bc \
           gsl-bin \
           libglib2.0-0 \
           libglu1-mesa-dev \
           libglw1-mesa \
           libgomp1 \
           libjpeg62 \
           libpng16-16 \
           libquadmath0 \
           libxm4 \
           libxmu6 \
           libxt6 \
           perl \
           libtiff5 \
           netpbm \
           software-properties-common \
           tcsh \
           xfonts-base \
           xvfb \
           zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sSL --retry 5 -o /tmp/libxp6.deb https://upenn.box.com/shared/static/reyyundn0l3guvjzghrrv6t4w6md2tjd.deb \
    && dpkg -i /tmp/libxp6.deb \
    && rm /tmp/libxp6.deb \
    && curl -sSL --retry 5 -o /tmp/libpng.deb http://snapshot.debian.org/archive/debian-security/20160113T213056Z/pool/updates/main/libp/libpng/libpng12-0_1.2.49-1%2Bdeb7u2_amd64.deb \
    && dpkg -i /tmp/libpng.deb \
    && rm /tmp/libpng.deb \
    && apt-get install -f --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && gsl2_path="$(find / -name 'libgsl.so.19' || printf '')" \
    && if [ -n "$gsl2_path" ]; then \
         ln -sfv "$gsl2_path" "$(dirname $gsl2_path)/libgsl.so.0"; \
    fi \
    && ldconfig \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Prepare environment
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        zlib1g-dev graphviz libfftw3-3 && \
    curl -sL https://deb.nodesource.com/setup_16.x | bash - && \
    apt-get install -y --no-install-recommends \
      nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN npm install -g svgo \
    && npm install -g bids-validator@1.8.4

# Install latest pandoc
RUN curl -o pandoc-2.2.2.1-1-amd64.deb -sSL "https://github.com/jgm/pandoc/releases/download/2.2.2.1/pandoc-2.2.2.1-1-amd64.deb" && \
    dpkg -i pandoc-2.2.2.1-1-amd64.deb && \
    rm pandoc-2.2.2.1-1-amd64.deb

# Install qt5.12.8
RUN add-apt-repository ppa:beineri/opt-qt-5.12.8-bionic \
    && apt-get update \
    && apt install -y --no-install-recommends \
    ${DSI_STUDIO_DEPS} ${MRTRIX3_DEPS} ${TORTOISE_DEPS} wget git binutils \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
COPY --from=build_dsistudio /opt/dsi-studio /opt/dsi-studio

# Install gcc-9
RUN add-apt-repository ppa:ubuntu-toolchain-r/test \
    && apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install ACPC-detect
WORKDIR /opt/art
ENV PATH="/opt/art/bin:$PATH"
RUN cd /opt/art \
    && curl -fsSL https://osf.io/73h5s/download \
    | tar xz --strip-components 1

# Install Workbench
RUN apt-get update && apt-get install -y curl unzip binutils
RUN mkdir /opt/workbench && \
    curl -sSLO https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v1.5.0.zip && \
    unzip workbench-linux64-v1.5.0.zip -d /opt && \
    rm workbench-linux64-v1.5.0.zip && \
    rm -rf /opt/workbench/libs_linux64_software_opengl /opt/workbench/plugins_linux64
ENV PATH="/opt/workbench/bin_linux64:$PATH" \
    LD_LIBRARY_PATH="/opt/workbench/lib_linux64:$LD_LIBRARY_PATH"

# Unless otherwise specified each process should only use one thread - nipype
# will handle parallelization
ENV \
    HOME="/home/qsiprep" \
    MKL_NUM_THREADS=1 \
    OMP_NUM_THREADS=1 \
    MRTRIX_NTHREADS=1 \
    KMP_WARNINGS=0 \
    CRN_SHARED_DATA=/niworkflows_data \
    IS_DOCKER_8395080871=1 \
    ARTHOME="/opt/art" \
    DIPY_HOME=/home/qsiprep/.dipy \
    QTDIR=$QT_BASE_DIR \
    PATH=$QT_BASE_DIR/bin:$PATH \
    LD_LIBRARY_PATH=$QT_BASE_DIR/lib/x86_64-linux-gnu:$QT_BASE_DIR/lib:$LD_LIBRARY_PATH \
    PKG_CONFIG_PATH=$QT_BASE_DIR/lib/pkgconfig:$PKG_CONFIG_PATH \
    LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/opt/conda/envs/qsirecon/lib/python3.10/site-packages/nvidia/cudnn/lib

WORKDIR /root/

# Precaching templates
COPY scripts/fetch_templates.py fetch_templates.py
RUN python fetch_templates.py && \
    rm fetch_templates.py && \
    find $HOME/.cache/templateflow -type d -exec chmod go=u {} + && \
    find $HOME/.cache/templateflow -type f -exec chmod go=u {} +

# Make it ok for singularity on CentOS
RUN strip --remove-section=.note.ABI-tag /opt/qt512/lib/libQt5Core.so.5.12.8 \
    && ldconfig

# Prepare atlases
RUN mkdir /atlas

# Download the AtlasPack atlases
RUN mkdir /atlas/AtlasPack
COPY --from=atlaspack /AtlasPack/tpl-fsLR_*.dlabel.nii /atlas/AtlasPack/
COPY --from=atlaspack /AtlasPack/tpl-MNI152NLin6Asym_*.nii.gz /atlas/AtlasPack/
COPY --from=atlaspack /AtlasPack/tpl-MNI152NLin2009cAsym_*.nii.gz /atlas/AtlasPack/
COPY --from=atlaspack /AtlasPack/atlas-4S*.tsv /atlas/AtlasPack/
COPY --from=atlaspack /AtlasPack/*.json /atlas/AtlasPack/
ENV QSIRECON_ATLASPACK /atlas/AtlasPack

# Reformat AtlasPack into a BIDS dataset
COPY scripts/fix_atlaspack.py fix_atlaspack.py
RUN python fix_atlaspack.py && rm fix_atlaspack.py

# Download the built-in atlases
RUN bash -c \
    'cd /atlas \
    && wget -nv https://upenn.box.com/shared/static/5k1tvg6soelxdhi9nvrkry6w0z49ctne.xz \
    && tar xvfJm 5k1tvg6soelxdhi9nvrkry6w0z49ctne.xz \
    && rm 5k1tvg6soelxdhi9nvrkry6w0z49ctne.xz'
ENV QSIRECON_ATLAS /atlas/qsirecon_atlases

# Download the PyAFQ atlases
RUN pyAFQ download

# Make singularity mount directories
RUN  mkdir -p /sngl/data \
  && mkdir /sngl/qsirecon-output \
  && mkdir /sngl/out \
  && mkdir /sngl/scratch \
  && mkdir /sngl/spec \
  && mkdir /sngl/eddy \
  && mkdir /sngl/filter \
  && chmod a+rwx /sngl/*
