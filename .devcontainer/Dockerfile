# Development Container Dockerfile, not for production
# Copyright 2026 Roland Metivier
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260713-slim

# NOTE: The Erlang/OTP version is the most recent supported version, not 29.x
# No need for builder/runner here
ARG DEVENV_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"

FROM ${DEVENV_IMAGE} AS devenv

ENV DEBIAN_FRONTEND=noninteractive

# Used for non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt update && \
    apt upgrade

# Separately from APT update/upgrade/install, we add the user and let them sudo
RUN groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd -s /bin/bash --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} && \
    apt install -y sudo git && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# We're done with auto-packaging
ENV DEBIAN_FRONTEND=dialog

USER ${USERNAME}
ENV HOME=/home/${USERNAME}