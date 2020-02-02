#!/bin/bash

# Only load db and modules if this script is being loaded for the first time (ie, docker run)
if [ -d "/root/temp" ]; then
# ------------ Begin Load Database ------------

if [ -z ${OPENMRS_MYSQL_HOST+x} ]; then
    OPENMRS_MYSQL_HOST=${MYSQL_PORT_3306_TCP_ADDR}
fi
echo "Using MySQL host: ${OPENMRS_MYSQL_HOST}"

if [ -z ${OPENMRS_MYSQL_PORT+x} ]; then
    OPENMRS_MYSQL_PORT=${MYSQL_PORT_3306_TCP_PORT}
fi
echo "Using MySQL port: ${OPENMRS_MYSQL_PORT}"

# Ensure mysql is up
while ! mysqladmin ping -h"$OPENMRS_MYSQL_HOST" -P $OPENMRS_MYSQL_PORT --silent; do
    echo "Waiting for database at '$OPENMRS_MYSQL_HOST:$OPENMRS_MYSQL_PORT'..."
    sleep 2
done

# Only set these variables if we're loading the demo data
if [ -z ${DEMO_DATA+x} ]; then
    echo "Demo data will not be loaded (specify the DEMO_DATA parameter to load demo data).";
else
    # ------------ Begin Configure Variables -----------------

    if [ -z ${DB_USER+x} ]; then
        echo "The mysql user parameter (DB_USER) must defined.";
        exit 1
    fi
    if [ -z ${DB_PASS+x} ]; then
        echo "The mysql password parameter (DB_PASS) must be defined.";
        exit 1
    fi

    if [ -z ${DB_NAME+x} ]; then
        DB_NAME=${DEFAULT_DB_NAME};
    fi
    echo "Database name will be '${DB_NAME}'"

    if [ -z ${OPENMRS_DB_USER+x} ]; then
        OPENMRS_DB_USER=${DEFAULT_OPENMRS_DB_USER};
    fi
    echo "OpenMRS DB user will be '${OPENMRS_DB_USER}'"

    if [ -z ${OPENMRS_DB_PASS+x} ]; then
        OPENMRS_DB_PASS=${DEFAULT_OPENMRS_DB_PASS};
    fi

    if [ -z ${OPENMRS_DATABASE_SCRIPT+x} ]; then
        OPENMRS_DATABASE_SCRIPT=${DEFAULT_OPENMRS_DATABASE_SCRIPT_PATH};
    fi

    # ------------ End Configure Variables -----------------

    # Check if the database already exists. If it does then do not create or import data but do ensure that the user has access
    if mysql -h $OPENMRS_MYSQL_HOST -P $OPENMRS_MYSQL_PORT -u $DB_USER --password=$DB_PASS -e "USE ${DB_NAME}"; then
        echo "Database '${DB_NAME}' already exists. Skipping database creation and import."
    else
        # Create database
        echo "Creating database..."
        echo "CREATE SCHEMA ${DB_NAME} DEFAULT CHARACTER SET utf8;" >> /root/temp/db/create_db.sql
        mysql -h $OPENMRS_MYSQL_HOST -P $OPENMRS_MYSQL_PORT -u $DB_USER --password=$DB_PASS < /root/temp/db/create_db.sql
        rm /root/temp/db/*.sql
        echo "Database created."

        # Load demo data into db
        echo "Loading demo data..."
        unzip -j ${OPENMRS_DATABASE_SCRIPT} -d /root/temp/db/
        SCRIPTS=/root/temp/db/*.sql

        for script in $SCRIPTS
        do
            mysql -h $OPENMRS_MYSQL_HOST -P $OPENMRS_MYSQL_PORT -u $DB_USER --password=$DB_PASS ${DB_NAME}  < $script
        done
        rm /root/temp/db/*.sql
        echo "Demo data loaded."

        # ------------ Begin Load OpenHMIS Demo Data -----------------

       if [ -z ${EXCLUDE_OPENHMIS+x} ]; then
           echo "Loading OpenHMIS demo data..."
           unzip -j ${OPENHMIS_LOCAL_DATABASE_SCRIPT_PATH} -d /root/temp/db/
           SCRIPTS=/root/temp/db/*.sql

           for script in $SCRIPTS
           do
               mysql -h $OPENMRS_MYSQL_HOST -P $OPENMRS_MYSQL_PORT -u $DB_USER --password=$DB_PASS ${DB_NAME}  < $script
           done

           rm /root/temp/db/*.sql
           echo "Demo OpenHMIS data loaded."
       fi

       # ------------ End Download OpenHMIS Demo Data -----------------
    fi

    # Create OpenMRS db user
    echo "Creating OpenMRS user..."
    echo "GRANT ALL ON ${DB_NAME}.* to '${OPENMRS_DB_USER}'@'%' identified by '${OPENMRS_DB_PASS}';" >> /root/temp/db/create_openmrs_user.sql
    mysql -h $OPENMRS_MYSQL_HOST -P $OPENMRS_MYSQL_PORT -u $DB_USER --password=$DB_PASS < /root/temp/db/create_openmrs_user.sql
    rm /root/temp/db/*.sql
    echo "OpenMRS user created."

    # Write openmrs-runtime.properties file with linked database settings
    OPENMRS_CONNECTION_URL="connection.url=jdbc\:mysql\://$OPENMRS_MYSQL_HOST\:$OPENMRS_MYSQL_PORT/${DB_NAME}?autoReconnect\=true&sessionVariables\=default_storage_engine\=InnoDB&useUnicode\=true&characterEncoding\=UTF-8"
    echo "${OPENMRS_CONNECTION_URL}" >> /root/temp/openmrs-runtime.properties
    echo "connection.username=${OPENMRS_DB_USER}" >> /root/temp/openmrs-runtime.properties
    echo "connection.password=${OPENMRS_DB_PASS}" >> /root/temp/openmrs-runtime.properties

    cp /root/temp/openmrs-runtime.properties ${OPENMRS_HOME}/
fi

# ------------ End Load Database ------------

# Copy base/dependency modules to module folder
echo "Copying module dependencies and reference application modules..."
mkdir -pv $OPENMRS_MODULES
cp /root/temp/modules/*.omod $OPENMRS_MODULES
echo "Modules copied."

# ------------ Begin Download OpenHMIS Modules -----------------
if [ -z ${EXCLUDE_OPENHMIS+x} ]; then
    echo "Downloading current OpenHMIS modules..."

    # Setup Variables
    DOWNLOAD_DIR=/root/temp/modules/openhmis
    TEAMCITY_URL="http://teamcity.openhmisafrica.org/"
    TEAMCITY_REST_ARTIFACT_URL="$TEAMCITY_URL/guestAuth/app/rest/builds/buildType:BUILD_TYPE/artifacts/children/"
    ARTIFACT_XPATH="string(/files/file/content/@href)"

    MODULE_PROJECT_NAMES=("commons_prod" "bbf_prod" "inv_prod" "cash_prod")

    # Clear openhmis module folder
    mkdir -pv ${DOWNLOAD_DIR}
    rm ${DOWNLOAD_DIR}/*.omod

    # Get current OpenHMIS module assets from TeamCity (master)
    for mod in "${MODULE_PROJECT_NAMES[@]}"
    do
        # Get artifact file list
        wget ${TEAMCITY_REST_ARTIFACT_URL/BUILD_TYPE/$mod} -O /root/temp/files.xml

        # Extract the omod file name (this should be the only artifact)
        FILE_URL=$(eval "xmllint --xpath '$ARTIFACT_XPATH' /root/temp/files.xml")

        # Get the omod artifact
        wget $TEAMCITY_URL$FILE_URL -P ${DOWNLOAD_DIR}

        # Cleanup
        rm /root/temp/files.xml
    done

    echo "OpenHMIS modules downloaded."

    cp ${DOWNLOAD_DIR}/*.omod ${OPENMRS_MODULES}/

    # ------------ End Download OpenHMIS Modules -----------------
fi

# Cleanup temp files
rm -r /root/temp
fi

# Set custom memory options for tomcat
export JAVA_OPTS="-Dfile.encoding=UTF-8 -server -Xms256m -Xmx1024m -XX:PermSize=256m -XX:MaxPermSize=512m"

# Run tomcat
catalina.sh run
