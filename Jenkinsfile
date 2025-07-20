pipeline {
    agent any
    environment {
        IMAGE_NAME = "smarthome_backend"
        SIM_IMAGE_NAME = "smarthome_simulator"
        FRONT_IMAGE_NAME = "smarthome_dashboard"
        GRAFANA_IMAGE_NAME = "smarthome_grafana"
    }
    stages {
        stage("clone backend repo") {
            steps {
                sh "git clone https://github.com/NadavNV/SmartHomeBackend"
                echo "Backend repo was cloned"
            }
        }
        stage("clone frontend repo") {
            steps {
                sh "git clone https://github.com/NadavNV/SmartHomeDashboard"
                echo "Frontend repo was cloned"
            }
        }
        stage("clone simulator repo") {
            steps {
                sh "git clone https://github.com/NadavNV/SmartHomeSimulator"
                echo "simulator repo was cloned"
            }
        }
        stage('create .env file') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'mongo-creds', usernameVariable: 'MONGO_USER', passwordVariable: 'MONGO_PASS')]) {
                    sh '''
                        echo "MONGO_USER=$MONGO_USER" > SmartHomeBackend/.env
                        echo "MONGO_PASS=$MONGO_PASS" >> SmartHomeBackend/.env
                        echo "BROKER_URL=mqtt-broker" >> SmartHomeBackend/.env
                    '''
                }
            }
        }
        stage("build backend images") {
            steps {
                echo "Building the Flask backend image"
                sh "docker build -t smarthome_backend_flask:${env.BUILD_NUMBER} -f SmartHomeBackend/flask.Dockerfile SmartHomeBackend"

                echo "Building clean production Nginx backend image"
                sh "docker build -t smarthome_backend_nginx:${env.BUILD_NUMBER} -f SmartHomeBackend/nginx.Dockerfile SmartHomeBackend"
                
                echo "Creating local nginx.conf for testing"
                writeFile file: 'SmartHomeBackend/nginx.conf', text: '''
            server {
                listen 5200;

                location / {
                    proxy_pass http://backend-flask:8000/;
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            }
        }
        '''
                echo "Building local testing Nginx backend image"
                sh "docker build -t smarthome_backend_nginx:${env.BUILD_NUMBER}_local -f SmartHomeBackend/nginx.Dockerfile SmartHomeBackend"
            }
        }
        stage("build frontend images") {
    steps {
        echo "Building clean production frontend image"
        sh "docker build -t ${env.FRONT_IMAGE_NAME}:${env.BUILD_NUMBER} SmartHomeDashboard"


        echo "Creating local nginx.conf for testing"
        writeFile file: 'SmartHomeDashboard/nginx.conf', text: '''
        server {
            listen 3001;
            root /usr/share/nginx/html;
            index index.html;
            etag on;
            location / {
                try_files $uri $uri/ /index.html;
            }
            location /api/ {
                proxy_pass http://test-container:5200;
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }
        }
        '''
        echo "Building local test image"
        sh "docker build -t ${env.FRONT_IMAGE_NAME}_local:${env.BUILD_NUMBER} --build-arg VITE_API_URL=http://test-container:5200 SmartHomeDashboard"

            }
        }

        stage("build simulator image") {
            steps {
                echo "Building the simulator image"
                sh "docker build -t ${env.SIM_IMAGE_NAME}:${env.BUILD_NUMBER} SmartHomeSimulator"
            }
        }
        stage("build Grafana image") {
            steps {
                echo "Building the Grafana image"
                dir("${env.WORKSPACE}"){
                sh "docker build -t ${env.GRAFANA_IMAGE_NAME}:${env.BUILD_NUMBER} -f monitoring/grafana/Dockerfile monitoring/grafana"
                }
            }
        }
        stage('test') {
            steps {
                echo "******testing the app******"
                // create a single network for all containers
                sh "docker network create test-net || true"
                // run and config a local mqtt-broker for testing
                sh '''
                    if [ ! -f "$WORKSPACE/mosquitto/mosquitto.conf" ]; then
                    echo -e "listener 1883\\nallow_anonymous true" > ./mosquitto.conf
                    MOUNT="-v $(pwd)/mosquitto.conf:/mosquitto/config/mosquitto.conf"
                    else
                    MOUNT="-v $WORKSPACE/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf"
                    fi

                    docker run -d \
                    --network test-net \
                    --name mqtt-broker \
                    $MOUNT \
                    eclipse-mosquitto
                '''
                sh "sleep 10"
                // get the mqtt broker ip for better code stability
                script {
                    env.BROKER_IP = sh(script: "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mqtt-broker", returnStdout: true).trim()
                    echo "mqtt broker IP: ${env.BROKER_IP}"
                }
                // run both backend containers (flask and nginx)
                sh "docker run -d --network test-net \
                    --env-file SmartHomeBackend/.env \
                    --name backend-flask \
                    --hostname backend-flask \
                    -e BROKER_URL=mqtt-broker \
                    -e BROKER_PORT=1883 \
                    -p 8000:8000 \
                    smarthome_backend_flask:${env.BUILD_NUMBER}"
                sh "docker run -d --network test-net \
                    --name test-container \
                    --hostname test-container \
                    -p 5200:5200 \
                    smarthome_backend_nginx:${env.BUILD_NUMBER}_local"
                sh "sleep 10"
                // get the nginx backend container ip for better code stability
                script {
                    def backendIp = sh(
                        script: '''
                            MAX_RETRIES=10
                            RETRY_DELAY=2
                            DEFAULT_IP="172.19.0.4"
                            IP=""
                            for i in $(seq 1 $MAX_RETRIES); do
                                IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' test-container 2>/dev/null)
                                if [[ -n "$IP" ]]; then
                                    break
                                else
                                    >&2 echo "Waiting for test-container IP... attempt $i"
                                    sleep $RETRY_DELAY
                                fi
                            done
                            if [[ -z "$IP" ]]; then
                                IP="$DEFAULT_IP"
                            fi
                            echo "$IP"
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "Backend IP: ${backendIp}"
                    env.BACKEND_URL = "http://${backendIp}:5200"
                }
                // run the simulator container
                sh "docker run -d --network test-net --name simulator-container --add-host test.mosquitto.org:${env.BROKER_IP} -e API_URL=${BACKEND_URL} ${env.SIM_IMAGE_NAME}:${env.BUILD_NUMBER}"
                // run the frontend container
                sh "docker run -d -p 3001:3001 --network test-net --name frontend-container --hostname frontend-container ${env.FRONT_IMAGE_NAME}_local:${env.BUILD_NUMBER}"
                // run the Prometheus container
                sh 'docker run -d --name prometheus -p 9090:9090 --network test-net -v "$(pwd)/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml" prom/prometheus:latest'
                // run the Grafana container
                sh "docker run -d --name grafana -p 3000:3000 --network test-net ${env.GRAFANA_IMAGE_NAME}:${env.BUILD_NUMBER}"
                sh "sleep 20"
                
                    // run the test script container
                sh """
                    docker run --rm \
                    --network test-net \
                    -v "${env.WORKSPACE}:/app" \
                    -w /app \
                    -e FRONTEND_URL=http://frontend-container:3001 \
                    -e BACKEND_URL=${BACKEND_URL} \
                    yardenziv/smarthome-test-runner:latest \
                    SmartHomeBackend/Test/test.py
                """

            }
            post {
                always {
            sh "docker rm -f test-container || true"
            sh "docker rm -f backend-flask || true"
            sh "docker rm -f simulator-container || true"
            sh "docker rm -f frontend-container || true"
            sh "docker rm -f mqtt-broker || true"
            sh "docker rm -f grafana || true"
            sh "docker rm -f prometheus || true"
            sh "docker network rm test-net || true"
                }
            }
        }
        stage('deploy') {
    steps {
        echo "******deploying a new version******"
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh """
                echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                
                docker tag smarthome_backend_flask:${env.BUILD_NUMBER} $DOCKER_USER/smarthome_backend_flask:V${env.BUILD_NUMBER}
                docker push $DOCKER_USER/smarthome_backend_flask:V${env.BUILD_NUMBER}
                docker tag smarthome_backend_flask:${env.BUILD_NUMBER} $DOCKER_USER/smarthome_backend_flask:latest
                docker push $DOCKER_USER/smarthome_backend_flask:latest

                docker tag smarthome_backend_nginx:${env.BUILD_NUMBER} $DOCKER_USER/smarthome_backend_nginx:V${env.BUILD_NUMBER}
                docker push $DOCKER_USER/smarthome_backend_nginx:V${env.BUILD_NUMBER}
                docker tag smarthome_backend_nginx:${env.BUILD_NUMBER} $DOCKER_USER/smarthome_backend_nginx:latest
                docker push $DOCKER_USER/smarthome_backend_nginx:latest

                docker tag ${env.SIM_IMAGE_NAME}:${env.BUILD_NUMBER} $DOCKER_USER/${env.SIM_IMAGE_NAME}:V${env.BUILD_NUMBER}
                docker push $DOCKER_USER/${env.SIM_IMAGE_NAME}:V${env.BUILD_NUMBER}
                docker tag ${env.SIM_IMAGE_NAME}:${env.BUILD_NUMBER} $DOCKER_USER/${env.SIM_IMAGE_NAME}:latest
                docker push $DOCKER_USER/${env.SIM_IMAGE_NAME}:latest

                docker tag ${env.FRONT_IMAGE_NAME}:${env.BUILD_NUMBER} $DOCKER_USER/${env.FRONT_IMAGE_NAME}:V${env.BUILD_NUMBER}
                docker push $DOCKER_USER/${env.FRONT_IMAGE_NAME}:V${env.BUILD_NUMBER}
                docker tag ${env.FRONT_IMAGE_NAME}:${env.BUILD_NUMBER} $DOCKER_USER/${env.FRONT_IMAGE_NAME}:latest
                docker push $DOCKER_USER/${env.FRONT_IMAGE_NAME}:latest

                docker tag ${env.GRAFANA_IMAGE_NAME}:${env.BUILD_NUMBER} $DOCKER_USER/${env.GRAFANA_IMAGE_NAME}:V${env.BUILD_NUMBER}
                docker push $DOCKER_USER/${env.GRAFANA_IMAGE_NAME}:V${env.BUILD_NUMBER}
                docker tag ${env.GRAFANA_IMAGE_NAME}:${env.BUILD_NUMBER} $DOCKER_USER/${env.GRAFANA_IMAGE_NAME}:latest
                docker push $DOCKER_USER/${env.GRAFANA_IMAGE_NAME}:latest

                docker logout
            """
        }
    }
}

    }

    post {
        always {
            cleanWs()
            sh '''
            for id in $(docker images -q smarthome_backend_flask | sort -u); do
            docker rmi -f $id || true
            done
        '''
        sh '''
            for id in $(docker images -q smarthome_backend_nginx | sort -u); do
            docker rmi -f $id || true
            done
        '''
        sh '''
            for id in $(docker images -q smarthome_backend_nginx_local | sort -u); do
            docker rmi -f $id || true
            done
        '''
            sh '''
            for id in $(docker images -q ${SIM_IMAGE_NAME} | sort -u); do
            docker rmi -f $id || true
            done
        '''
        sh '''
            for id in $(docker images -q ${FRONT_IMAGE_NAME} | sort -u); do
            docker rmi -f $id || true
            done
        '''
        sh '''
            for id in $(docker images -q ${FRONT_IMAGE_NAME}_local | sort -u); do
            docker rmi -f $id || true
            done
        '''
        sh '''
            for id in $(docker images -q ${GRAFANA_IMAGE_NAME} | sort -u); do
            docker rmi -f $id || true
            done
        '''
        }
    }
}