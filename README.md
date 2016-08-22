## VDocker
Translate "docker run" arguments to host paths when run within a
container.

When mounting docker volumes from within a container, communicating via
a shared docker.sock, the volume source must be specified in terms of
the host. This puts a burden on the container to keep track of resources
which it shouldn't need to know about.

vdocker encapsulates the mapping between "container" paths and "host"
paths, so scripts within a container that want to run their own docker
containers don't need to know where they're running from. The main
caveat (and it's a big one), is that all "source" volumes need to be
within existing docker volumes used by the container. Another caveat is
that "ro" mounts are not fully supported, when there is overlap between
volumes.

For example, assuming a container has been launched (directly on the
host) via:

    docker run -d -v /var/run/docker.sock -v /path/to/host/source:/src anImage

Then running the following within the anImage container:

    vdocker.sh run -d -v /src/a/path/within/src:/subsrc anotherImage

Would translate to:

    docker run -d -v /path/to/host/source/a/path/within/src:/subsrc anotherImage
