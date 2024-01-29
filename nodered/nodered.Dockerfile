FROM nodered/node-red:3.0.2

RUN npm install node-red-contrib-kafka-manager && \
    npm install node-red-contrib-flightaware && \
    npm install node-red-contrib-flow-manager && \
    npm install node-red-node-email && \
    npm install node-red-contrib-string && \
    npm install node-red-contrib-postgresql
