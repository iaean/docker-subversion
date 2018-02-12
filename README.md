# docker-subversion
Docker container for Subversion with WebSVN

Runs apache and svnserve to provide access via `svn://` and `http://`.

### Building the docker image
Use docker to build the image as you normaly would:
`docker build --rm=true --tag="image_websvn" ./`
