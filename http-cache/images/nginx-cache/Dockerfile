FROM alpine:3.20

RUN apk add --no-cache nginx nginx-mod-http-brotli nginx-mod-http-cache-purge nginx-mod-http-lua nginx-mod-http-vts

CMD [ "/bin/sh", "-c", "echo \"resolver $(grep nameserver /etc/resolv.conf | head -n 1  | cut -d ' ' -f 2) ipv6=off;\" > /etc/nginx/resolver.conf && nginx -g \"daemon off;\"" ]
