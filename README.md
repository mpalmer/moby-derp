This tool is designed to securely manage a group of related containers, known
colloquially as a ["pod"](https://kubernetes.io/docs/concepts/workloads/pods/pod/),
under the Moby container management system.

It has no aspirations to be a fully-fledged multi-host container orchestation system;
instead, it is simply a means to create and maintain a pod of containers.

The most common use-case for `moby-derp` is to allow unprivileged users to
define a pod, and then allow those users to execute `moby-derp` as a privileged
user via `sudo`.  Since this removes the need for random users to have direct
control over the moby daemon, a lot of potential [privilege escalation
attacks](https://fosterelli.co/privilege-escalation-via-docker.html)
facilitated by moby's security model are thwarted.


# Installation

It's a gem:

    gem install moby-derp

If you're the sturdy type that likes to run from git:

    rake install

Or, if you've eschewed the convenience of Rubygems entirely, then you
presumably know what to do already.


# Usage

The main interface for `moby-derp` is the command-line tool of the same name.
It takes as its sole argument a YAML file containing a whole pile of information
about the pod and how you want the containers within it to be run.  A very simple
example file might look like this:

    publish:
      - 80:80
    containers:
      nginx:
        image: 'nginx:latest'
        mounts:
          - source: nginx
            target: /etc/nginx
          - source: content
            target: /var/www
      content_puller:
        image: 'example/content_puller'
        mounts:
          - source: content
            target: /puller

For full details on exactly what can be done using the pod configuration file,
please see [`example.yml`](example.yml), which is a heavily-commented example
of every possible configuration option that can be set.

Once you have a pod config, saved in, say, `my-pod.yml`, you can tell `moby-derp`
to run it:

    moby-derp ./my-pod.yml

Often, however, you won't have the ability to contact the moby daemon directly,
so you'll run `moby-derp` via `sudo`:

    sudo moby-derp ./my-pod.yml

Where this comes in handy is that `sudo` can be configured to restrict the
set of commands that a given user is allowed to run.  So, for instance, if the
user who wants to run this pod is named `bob` on the system, I can put this
in my `/etc/sudoers`:

    bob ALL=(root) NOPASSWD: /usr/local/bin/moby-derp */my-pod.yml

Then `bob` (and *only* `bob`) can run

    sudo moby-derp ./my-pod.yml

The name of the pod is taken from the name of the file, with any extension
removed.  This is used as the prefix for the name of all containers in the pod.


## System Configuration

Some aspects of `moby-derp`'s operation are security-sensitive, and thus shouldn't
be able to be modified by the ordinary user.  There is a
system-wide configuration file for this purpose, by default located at
`/etc/moby-derp.yml`.

Its structure is quite simple.  A full example looks like this:

    mount_root: '/srv/docker'
    port_whitelist:
      80: web-server
      443: web-server
      25: mail-server
      1337: bobblehead

The keys are:

* **`mount_root`**: the directory on disk where all mounts for all pods will
  be stored.  For security, the filesystem on which this location resides
  should really be mounted `nosuid` and, if you can swing it, even `noexec`.
  The directory specified by this option must already exist.

* **`port_whitelist`**: a map of port numbers and the pod which should be
  allowed to map them.  Any port which is not listed here cannot be explicitly
  mapped by a pod, and only the pod named in the mapping can publish on the
  specified port.

* **`network_name`**: specify a network name to attach all pods to, if you
  don't like Moby's default `bridge` network.

* **`use_host_resolv_conf`**: Moby has some... strange ideas about what
  constitutes DNS records (like thinking that PTR records can only be for
  rDNS).  At the same time, you cannot, by purely Moby-sanctioned means,
  disable the spectacularly broken DNS proxy that is inflicted on you if you
  decide to use a custom network.  The only feasible workaround that I have
  discovered is to straight-up bind mount the host's `/etc/resolv.conf` into
  every single container.  If you, too, like your DNS resolution to work
  properly when you use a non-default network, set this option to true.

  Bear in mind, when constructing your host's `/etc/resolv.conf` file, that the
  host's conception of "localhost" is different to each container's
  "localhost"; so pointing to your local caching resolver using `127.0.0.1`
  will not end in happiness and puppies.

If you wish to modify the location of the `moby-derp` system-wide configuration
file, you can do so by setting the `MOBY_DERP_SYSTEM_CONFIG_FILE` environment
variable.  Note, however, that it is a terrible idea to let ordinary users control
that environment variable, so if you want to set it, please write a small
wrapper script, like this:

    #!/bin/sh

    set -e

    export MOBY_DERP_SYSTEM_CONFIG_FILE=/opt/srv/etc/moby-derp/moby-derp.yaml

    exec /usr/local/bin/moby-derp "$@"

You can also set other relevant environment variables, such as `DOCKER_HOST`,
in a like manner, if required.


## Running `moby-derp` as a non-root user

If you are properly cautious, it is a fine idea to not allow `moby-derp` itself
root access to the system.  This is possible, although it comes with a few
caveats:

* The `sudoers` config needs to be adjusted appropriately, to specify the
  user that you want to run `moby-derp` as;

* The system-wide configuration file needs to be readable by whatever user
  you run `moby-derp` as;

* When running `moby-derp`, the user to run it as needs to be specified on
  the command line, like so:

        sudo -u moby-derper moby-derp ./my-pod.yml

* The user that runs `moby-derp` must have access to the Docker control socket;
  by default that means making that user a member of the `docker` group;

* The user that runs `moby-derp` must have write access to the `mount_root`
  directory, so it can create pod mount roots.


# Security

This section discusses the security model and guarantees of `moby-derp`.  It
isn't necessary to simply use `moby-derp` in most circumstances.

The fundamental principle of `moby-derp` is that users are given control over
a certain portion of the container and filesystem namespace, by virtue of their
ability to run `moby-derp` with a specific filename -- and nothing more.  The
containers that a user can modify, and the portions of the filesystem that they
can write files to, is strictly limited by the tool.


## Container namespace

All containers associated with a pod are named for the filename that is passed
to `moby-derp`.  This means that, yes, different users need to use different
filenames.  The benefit of this is that the `sudo` configuration becomes a lot
easier to audit -- the pod name is right there.

This means that no matter what a user does, they cannot have any effect on any
container which is not named for the pod they're manipulating.  There are also
safety valves around `moby-derp`-managed containers being labelled as such, so
that in the event that someone does inadvertently name a container in such a
way that it can be manipulated by another user via `moby-derp`, it should still
be safe from tampering.


## Filesystem

All references to the host side of mounts within the pod are made relative to
the pod mount root, which is a subdirectory under the directory specified
under the `mount_root` system configuration named for the pod.  As one would
expect, attempts to use absolute paths, or parent directory references (via
`..`) will not be looked upon kindly.

To prevent attacks around modifying file permissions in the container and then
using that on the host to escalate privileges, it is *STRONGLY* recommended
that the filesystem which holds the `mount_root` be mounted `nosuid`, and even
`noexec` if that isn't going to get in the way of your use-case.  You
can also use the `userns-remap` feature if that is compatible with your use
of Moby.


## Network ports

By default, `moby-derp` will not allow containers to publish to specific ports
on the host.  The expectation is that network traffic will, for the most part,
rely on direct connection to containers, using either host-based proxies,
overlay networks, or new-fangled technologies like IPv6.  This prevents
misbehaving pods from capturing ports intended for use by other pods.  Pods can
still publish to ephemeral ports (using the `:containerPort` syntax, or
`publish_all: true`) if they wish.

If a pod *does* need to bind to a specific host port, then that pod/port pair
should be whitelisted in the [system configuration file](#system-configuration).


# Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).


# Licence

Unless otherwise stated, everything in this repo is covered by the following
copyright notice:

    Copyright (C) 2019  Matt Palmer <matt@hezmatt.org>

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License version 3, as
    published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
