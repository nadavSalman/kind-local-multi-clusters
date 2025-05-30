FROM nginx:alpine

# Copy custom NGINX config
COPY default.conf /etc/nginx/conf.d/default.conf

# Optional: If you need to manipulate /etc/hosts inside the container
# COPY entrypoint.sh /entrypoint.sh
# RUN chmod +x /entrypoint.sh

# Expose port 80
EXPOSE 80

# Start NGINX (or entrypoint script if needed)
CMD ["nginx", "-g", "daemon off;"]
