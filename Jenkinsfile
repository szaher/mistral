pipeline {
  agent any
  stages {
    stage('Debug: List RDS') {
      parallel {
        stage('Debug: List RDS') {
          steps {
            sh 'aws rds describe-db-instances'
          }
        }
        stage('List files') {
          steps {
            sh 'ls -lh'
          }
        }
        stage('Msg') {
          steps {
            echo 'Welcome'
          }
        }
      }
    }
    stage('Disable DNS') {
      parallel {
        stage('Disable DNS') {
          steps {
            echo 'Disabling DNS'
          }
        }
        stage('DNS') {
          steps {
            sh 'aws route53 get-hosted-zone'
          }
        }
      }
    }
    stage('Promote') {
      steps {
        echo 'Promoting Read Replica'
      }
    }
    stage('Notify') {
      parallel {
        stage('Notify') {
          steps {
            emailext(subject: 'Test Email', body: 'Test Body', from: 'szaher@hpe.com', mimeType: 'plain/text', to: 'saad.zaher@hpe.com')
          }
        }
        stage('Verify') {
          steps {
            echo 'Try to connect to the db'
          }
        }
      }
    }
  }
  environment {
    Test = 'OKE'
  }
}