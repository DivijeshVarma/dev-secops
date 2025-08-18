#FROM nginx:1.29.1
FROM nginx:1.29.1-alpine
COPY ./index.html /usr/share/nginx/html
EXPOSE 80
