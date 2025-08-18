#FROM nginx:1.29.1-alpine
FROM nginx:1.29.1
COPY ./index.html /usr/share/nginx/html
EXPOSE 80
