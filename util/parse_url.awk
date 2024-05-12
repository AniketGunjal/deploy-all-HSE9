#!/bin/awk -f
# Take a URL from the input and output scheme, host and port separated by ;
{
    url=$1;

    scheme="http";
    port=80;

    # Find and remove scheme
    i = index(url,"://");
    if (i > 0) {
        scheme=substr(url,1,i-1);
        url=substr(url,i+3);
        if (scheme == "https") {
            port=443;
        }
    }

    # Find and extract port
    i = index(url,":");
    if (i > 0) {
        port=substr(url,i+1);
        url=substr(url,1,i-1);
    }

    printf("%s;%s;%s\n", scheme, url, port);
}
