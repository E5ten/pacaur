FROM archlinux:latest
RUN pacman -Syyu --noconfirm
RUN pacman -S --noconfirm git base-devel
RUN git clone https://aur.archlinux.org/pacaur.git

# set up the packager user
RUN useradd --create-home packager
#NOTE: to consider at some point: COPY packager-actions /etc/sudoers.d/

RUN pacman -S --noconfirm meson gtest gmock expac jq

USER packager
WORKDIR /home/packager/
RUN git clone https://aur.archlinux.org/pod2man.git
WORKDIR /home/packager/pod2man/
RUN makepkg --noconfirm
USER root
WORKDIR /home/packager/
RUN pacman --noconfirm -U */*.pkg.tar.zst


USER packager
WORKDIR /home/packager/
RUN git clone https://aur.archlinux.org/auracle-git.git
WORKDIR /home/packager/auracle-git/
RUN makepkg --noconfirm
USER root
WORKDIR /home/packager/
RUN pacman --noconfirm -U */*.pkg.tar.zst


USER packager
WORKDIR /home/packager/
RUN git clone https://aur.archlinux.org/pacaur.git
WORKDIR /home/packager/pacaur/
RUN makepkg --noconfirm
USER root
WORKDIR /home/packager/
RUN pacman --noconfirm -U */*.pkg.tar.zst


USER root
WORKDIR /home/packager/
RUN pacman --noconfirm -U */*.pkg.tar.zst

# FROM here pacaur is installed.
# Uncomment commands below,
# switch to `packager` user ( so pacaur does not complain that runs as root.)
# and enjoy pacaur installed + user for using it inside your container!
#
# USER packager
# WORKDIR /home/packager/
# RUN pacaur ... enjoy using pacaur inside your container
