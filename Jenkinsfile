pipeline {
  agent any
  stages {
    stage('Checkout') {
      steps {
        git(url: 'ssh://git-codecommit.us-east-1.amazonaws.com/v1/repos/craff', branch: 'master', credentialsId: 'testcred')
      }
    }
    stage('Configure') {
      steps {
        sh '''# configure terraform 
ls -lh
'''
      }
    }
    stage('Plan') {
      steps {
        sh '''source master.sh
cd main-cluster
terraform init -state master.tfstate'''
      }
    }
    stage('Build-Master') {
      steps {
        sh '''source master.sh
cd main-cluster


terraform apply -state master.tfstate'''
      }
    }
    stage('Plan-Replica') {
      steps {
        sh '''source replica.sh
cd main-cluster
terraform init -state replica.tfstate
terraform plan -state replica.tfstate'''
      }
    }
    stage('Build-Replica') {
      steps {
        sh '''source replica.sh

cd main-cluster

terraform apply -state replica.tfstate
'''
      }
    }
    stage('Verify') {
      steps {
        sh 'aws --help'
      }
    }
  }
}