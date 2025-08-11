
# devops0405-docker-flask-app

This is a simple Flask-based web application that returns "Hello, World!" when accessed.  
The project demonstrates how to containerize a Python application using Docker and run it locally or from Docker Hub.

---

## 📁 Project Structure

.
├── FlaskApp.py
├── Dockerfile
├── docker-compose.yml
└── README.md


---

## 🚀 How to Build and Run the Application

### 1. Clone the project

git clone https://github.com/azerez/devops0405-p1-docker.git
cd devops0405-p1-docker


### 2. Build the Docker image


docker build -t flask-app:v1 .


### 3. Run the container locally


docker run -d -p 5000:5000 flask-app:v1


Visit: [http://localhost:5000]

---

## ☁️ Push to Docker Hub

Make sure you are logged in:

docker login


Tag the image and push:


docker tag flask-app:v1 erezazu/devops0405-docker-flask-app:v1
docker push erezazu/devops0405-docker-flask-app:v1


---

## 🐳 Run the Container from Docker Hub


docker run -d -p 5000:5000 erezazu/devops0405-docker-flask-app:v1


---

## 🧱 Run Using docker-compose


docker-compose up 

*** Option - build image with --build)

Visit: [http://localhost:5000]

---

## 🔍 What to Expect

Response in browser or curl:

"Hello, World!"

---

## 📌 Author

- **Name:** Erez Azoulay  
- **Course:** DevOps 0405  
- **Docker Hub:** [erezazu](https://hub.docker.com/u/erezazu)
