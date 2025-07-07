#!/bin/bash

# Update package index
sudo apt-get update

# Install prerequisites
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# Add Docker's official repository
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Update package index again
sudo apt-get update

# Install Docker
sudo apt-get install -y docker-ce

# Install Docker Compose (latest version)
DOCKER_COMPOSE_VERSION="1.29.2"  # Change this to the desired version
sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Apply executable permissions to the binary
sudo chmod +x /usr/local/bin/docker-compose

# Add current user to the docker group
sudo usermod -aG docker $USER

# Print installation details
echo "Docker and Docker Compose have been installed."
echo "You may need to log out and back in for group changes to take effect."
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
