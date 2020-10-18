# Builder for custom Nginx Docker images

Based mainly on
[Tinkoff's Nginx-builder](https://github.com/TinkoffCreditSystems/Nginx-builder/),
which allows to easily build Nginx with custom modules, such as mod-vts, headers-more,
http_substitutions_filter and so on.

The main goal of this project is to adopt Nginx-builder for building Nginx Docker images
instead of DEB and RPM packages. This was done by using multi-stage Docker build: on the
first stage, Debian-based Python image builds Nginx DEB packages, and on the second stage,
this packages will be installed in the clean Debian image.

The skeleton of nginx install command, and all entrypoint scripts are taken from
[official Nginx dockerization](https://github.com/nginxinc/docker-nginx). However,
the resulting image, due to multistage build, is 1.5x times smaller than official one
without Perl (~85 Mb vs ~130 Mb, and, yeah,
[don't trust sizes at DockerHub](https://github.com/docker/hub-feedback/issues/242),
just look at the `docker images` output).

# Building

To build Nginx with current config, which includes
[mod-vts](https://github.com/vozlt/nginx-module-vts),
[headers-more](https://github.com/openresty/headers-more-nginx-module),
[http_subs_filter](https://github.com/yaoweibin/ngx_http_substitutions_filter_module),
[geoip2](https://github.com/leev/ngx_http_geoip2_module) (yes, external dependency
libmaxminddb0 will be added automatically, +100 kilobytes), simply type something like
```
docker build . --build-arg="NGINX_VERSION=1.19.1" -t "your-repo/nginx:1.19.1-custom"
```

You can set Nginx version via `NGINX_VERSION` build argument, and specify sources and 
versions of additional modules (as well as custom build options) via `config.yaml`.

Build was tested with modules listed above with Nginx 1.18.0 and 1.19.3.

# FAQ

- **Does it support Alpine-based builds?** No. Sorry. Nginx-builder supports only RPM
  and Deb packages. If someone someday will add Alpine support to Nginx-builder, I'll
  be happy to do my part of job.
- **Is this version of Nginx-builder just a copy of upstream?** No. Here I've fixed
  some bugs, especially one preventing modules to download from Git (`git.Repo()`
  instead of `git.Repo` in `builder/src/downloader.py:112:20`). Not all (there are
  too many of them), but ones which bothered me. Also added a possibility to specify
  Nginx version in command line, overriding the value from config (which greatly 
  simplifies automated builds for a different Nginx versions, see example
  in `.gitlab-ci.yml`).
