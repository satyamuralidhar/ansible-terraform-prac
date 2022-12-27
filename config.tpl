#!/bin/bash
# Run me with superuser privileges
sudo useradd -m -p satya satya
echo 'satya  ALL=(ALL:ALL) ALL' >> visudo
