pipeline {
  agent any
  stages {
    stage('First') {
      parallel {
        stage('First') {
          steps {
            sh 'ls -lh'
          }
        }
        stage('Welcome') {
          steps {
            echo 'welcome'
          }
        }
      }
    }
    stage('test') {
      steps {
        sh 'ls -lh'
      }
    }
  }
}