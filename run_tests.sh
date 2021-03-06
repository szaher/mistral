#!/bin/bash

set -eu

function usage {
  echo "Usage: $0 [OPTION]..."
  echo "Run Mistral's test suite(s)"
  echo ""
  echo "  -V, --virtual-env           Always use virtualenv.  Install automatically if not present"
  echo "  -N, --no-virtual-env        Don't use virtualenv.  Run tests in local environment"
  echo "  -s, --no-site-packages      Isolate the virtualenv from the global Python environment"
  echo "  -r, --recreate-db           Recreate the test database (deprecated, as this is now the default)."
  echo "  -n, --no-recreate-db        Don't recreate the test database."
  echo "  -f, --force                 Force a clean re-build of the virtual environment. Useful when dependencies have been added."
  echo "  -u, --update                Update the virtual environment with any newer package versions"
  echo "  -p, --pep8                  Just run PEP8 and HACKING compliance check"
  echo "  -P, --no-pep8               Don't run static code checks"
  echo "  -c, --coverage              Generate coverage report"
  echo "  -d, --debug                 Run tests with testtools instead of testr. This allows you to use the debugger."
  echo "  -h, --help                  Print this usage message"
  echo "  --virtual-env-path <path>   Location of the virtualenv directory"
  echo "                               Default: \$(pwd)"
  echo "  --virtual-env-name <name>   Name of the virtualenv directory"
  echo "                               Default: .venv"
  echo "  --tools-path <dir>          Location of the tools directory"
  echo "                               Default: \$(pwd)"
  echo "  --db-type <name>            Database type"
  echo "                               Default: sqlite"
  echo "  --parallel <bool>           Determines whether the tests are run in one thread or not"
  echo "                               Default: false"
  echo ""
  echo "Note: with no options specified, the script will try to run the tests in a virtual environment,"
  echo "      If no virtualenv is found, the script will ask if you would like to create one.  If you "
  echo "      prefer to run tests NOT in a virtual environment, simply pass the -N option."
  exit
}

function process_options {
  i=1
  while [ $i -le $# ]; do
    case "${!i}" in
      -h|--help) usage;;
      -V|--virtual-env) always_venv=1; never_venv=0;;
      -N|--no-virtual-env) always_venv=0; never_venv=1;;
      -s|--no-site-packages) no_site_packages=1;;
      -r|--recreate-db) recreate_db=1;;
      -n|--no-recreate-db) recreate_db=0;;
      -f|--force) force=1;;
      -u|--update) update=1;;
      -p|--pep8) just_pep8=1;;
      -P|--no-pep8) no_pep8=1;;
      -c|--coverage) coverage=1;;
      -d|--debug) debug=1;;
      --virtual-env-path)
        (( i++ ))
        venv_path=${!i}
        ;;
      --virtual-env-name)
        (( i++ ))
        venv_dir=${!i}
        ;;
      --tools-path)
        (( i++ ))
        tools_path=${!i}
        ;;
      --db-type)
        (( i++ ))
        db_type=${!i}
        ;;
      --parallel)
        (( i++ ))
        parallel=${!i}
        ;;
      -*) testropts="$testropts ${!i}";;
      *) testrargs="$testrargs ${!i}"
    esac
    (( i++ ))
  done
}

db_type=${db_type:-sqlite}
parallel=${parallel:-false}
tool_path=${tools_path:-$(pwd)}
venv_path=${venv_path:-$(pwd)}
venv_dir=${venv_name:-.venv}
with_venv=tools/with_venv.sh
always_venv=0
never_venv=0
force=0
no_site_packages=0
installvenvopts=
testrargs=
testropts=
wrapper=""
just_pep8=0
no_pep8=0
coverage=0
debug=0
recreate_db=1
update=0

LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_ALL=C

CI_PROJECT=${CI_PROJECT:-""}

process_options $@
# Make our paths available to other scripts we call
export venv_path
export venv_dir
export venv_name
export tools_dir
export venv=${venv_path}/${venv_dir}

if [ $no_site_packages -eq 1 ]; then
  installvenvopts="--no-site-packages"
fi


function setup_db {
    case ${db_type} in
        sqlite )
            rm -f tests.sqlite
            ;;
        "postgresql" | "mysql" )
            dbname="openstack_citest"
            username="openstack_citest"
            password="openstack_citest"
            ;;
    esac
}

function setup_db_pylib {
    case ${db_type} in
        postgresql )
            echo "Installing python library for PostgreSQL."
            ${wrapper} pip install psycopg2
            ;;
        mysql )
            echo "Installing python library for MySQL"
            ${wrapper} pip install mysql-python
            ;;
    esac
}

function setup_db_cfg {
    case ${db_type} in
        sqlite )
            rm -f .mistral.conf
            ;;
        "postgresql" | "mysql" )
            oslo-config-generator --config-file \
                ./tools/config/config-generator.mistral.conf \
                --output-file .mistral.conf
            sed -i "s/#connection = <None>/connection = $db_type:\/\/$username:$password@localhost\/$dbname/g" .mistral.conf
            ;;
    esac
}

function cleanup {
    rm -f .mistral.conf
}

function run_tests {
  # Cleanup *pyc
  ${wrapper} find . -type f -name "*.pyc" -delete

  if [ $debug -eq 1 ]; then
    if [ "$testropts" = "" ] && [ "$testrargs" = "" ]; then
      # Default to running all tests if specific test is not
      # provided.
      testrargs="discover ./mistral/tests/unit"
    fi
    ${wrapper} python -m testtools.run $testropts $testrargs

    # Short circuit because all of the testr and coverage stuff
    # below does not make sense when running testtools.run for
    # debugging purposes.
    return $?
  fi

  if [ $coverage -eq 1 ]; then
    TESTRTESTS="$TESTRTESTS --coverage"
  else
    TESTRTESTS="$TESTRTESTS --slowest"
  fi

  # Just run the test suites in current environment
  set +e
  testrargs=$(echo "$testrargs" | sed -e's/^\s*\(.*\)\s*$/\1/')
  if [ $parallel = true ]
  then
    runoptions="--subunit"
  else
    runoptions="--concurrency=1 --subunit"
  fi
  TESTRTESTS="$TESTRTESTS --testr-args='$runoptions $testropts $testrargs'"
  OS_TEST_PATH=$(echo $testrargs|grep -o 'mistral\.tests[^[:space:]:]*\+'|tr . /)
  if [ -d "$OS_TEST_PATH" ]; then
      wrapper="OS_TEST_PATH=$OS_TEST_PATH $wrapper"
  elif [ -d "$(dirname $OS_TEST_PATH)" ]; then
      wrapper="OS_TEST_PATH=$(dirname $OS_TEST_PATH) $wrapper"
  fi
  echo "Running ${wrapper} $TESTRTESTS"
  bash -c "${wrapper} $TESTRTESTS | ${wrapper} subunit2pyunit"
  RESULT=$?
  set -e

  copy_subunit_log
  cleanup

  if [ $coverage -eq 1 ]; then
    echo "Generating coverage report in covhtml/"
    # Don't compute coverage for common code, which is tested elsewhere
    ${wrapper} coverage combine
    ${wrapper} coverage html --include='mistral/*' -d covhtml -i
  fi

  return $RESULT
}

function copy_subunit_log {
  LOGNAME=$(cat .testrepository/next-stream)
  LOGNAME=$(($LOGNAME - 1))
  LOGNAME=".testrepository/${LOGNAME}"
  cp $LOGNAME subunit.log
}

function run_pep8 {
  echo "Running flake8 ..."

  ${wrapper} flake8
}


TESTRTESTS="python setup.py testr"

if [ $never_venv -eq 0 ]
then
  # Remove the virtual environment if --force used
  if [ $force -eq 1 ]; then
    echo "Cleaning virtualenv..."
    rm -rf ${venv}
  fi
  if [ $update -eq 1 ]; then
      echo "Updating virtualenv..."
      python tools/install_venv.py $installvenvopts
  fi
  if [ -e ${venv} ]; then
    wrapper="${with_venv}"
  else
    if [ $always_venv -eq 1 ]; then
      # Automatically install the virtualenv
      python tools/install_venv.py $installvenvopts
      wrapper="${with_venv}"
    else
      echo -e "No virtual environment found...create one? (Y/n) \c"
      read use_ve
      if [ "x$use_ve" = "xY" -o "x$use_ve" = "x" -o "x$use_ve" = "xy" ]; then
        # Install the virtualenv and run the test suite in it
        python tools/install_venv.py $installvenvopts
        wrapper=${with_venv}
      fi
    fi
  fi
fi

# Delete old coverage data from previous runs
if [ $coverage -eq 1 ]; then
    ${wrapper} coverage erase
fi

if [ $just_pep8 -eq 1 ]; then
    run_pep8
    exit
fi

if [ $recreate_db -eq 1 ]; then
    setup_db
fi

setup_db_pylib
setup_db_cfg
run_tests

# NOTE(sirp): we only want to run pep8 when we're running the full-test suite,
# not when we're running tests individually. To handle this, we need to
# distinguish between options (testropts), which begin with a '-', and
# arguments (testrargs).
if [ -z "$testrargs" ]; then
  if [ $no_pep8 -eq 0 ]; then
    run_pep8
  fi
fi
