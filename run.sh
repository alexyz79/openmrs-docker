#!/bin/bash

# Only load db and modules if this script is being loaded for the first time (ie, docker run)
if [ -d "/root/temp" ]; then
# ------------ Begin Load Database ------------

if [ -z ${DEMO_DATA+x} ]; then
    echo "Demo data will not be loaded (specify the DEMO_DATA parameter to load demo data).";
else
    # ------------ Begin Configure Variables -----------------

    # Only set these variables if we're loading the demo data
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
    if mysql -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT -u $DB_USER --password=$DB_PASS -e "USE ${DB_NAME}"; then
        echo "Database '${DB_NAME}' already exists. Database creation and import will not occur."
    else
        # Create database
        echo "Creating database..."
        echo "CREATE SCHEMA ${DB_NAME} DEFAULT CHARACTER SET utf8;" >> /root/temp/db/create_db.sql
        mysql -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT -u $DB_USER --password=$DB_PASS < /root/temp/db/create_db.sql
        rm /root/temp/db/*.sql
        echo "Database created."

        # Load demo data into db
        echo "Loading demo data..."
        unzip -j ${OPENMRS_DATABASE_SCRIPT} -d /root/temp/db/
        SCRIPTS=/root/temp/db/*.sql

        for script in $SCRIPTS
        do
            mysql -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT -u $DB_USER --password=$DB_PASS ${DB_NAME}  < $script
        done
        echo "Demo data loaded."
    fi

    # Create OpenMRS db user
    echo "Creating OpenMRS user..."
    echo "GRANT ALL ON ${DB_NAME}.* to '${OPENMRS_DB_USER}'@'%' identified by '${OPENMRS_DB_PASS}';" >> /root/temp/db/create_openmrs_user.sql
    mysql -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT -u $DB_USER --password=$DB_PASS < /root/temp/db/create_openmrs_user.sql
    rm /root/temp/db/*.sql
    echo "OpenMRS user created."

    # Write openmrs-runtime.properties file with linked database settings
    OPENMRS_CONNECTION_URL="connection.url=jdbc\:mysql\://$MYSQL_PORT_3306_TCP_ADDR\:$MYSQL_PORT_3306_TCP_PORT/${DB_NAME}?autoReconnect\=true&sessionVariables\=default_storage_engine\=InnoDB&useUnicode\=true&characterEncoding\=UTF-8"
    echo "${OPENMRS_CONNECTION_URL}" >> /root/temp/openmrs-runtime.properties
    echo "connection.username=${OPENMRS_DB_USER}" >> /root/temp/openmrs-runtime.properties
    echo "connection.password=${OPENMRS_DB_PASS}" >> /root/temp/openmrs-runtime.properties

    cp /root/temp/openmrs-runtime.properties ${OPENMRS_HOME}/
fi

# ------------ End Load Database ------------

# ------------ Begin Download OpenHMIS Modules -----------------

echo "Downloading current OpenHMIS modules..."

# Setup Variables
DOWNLOAD_DIR=/root/temp/modules/openhmis
TEAMCITY_URL="http://build.openhmisafrica.org/teamcity"
TEAMCITY_REST_ARTIFACT_URL="$TEAMCITY_URL/guestAuth/app/rest/builds/buildType:BUILD_TYPE/artifacts/children/"
ARTIFACT_XPATH="string(/files/file/content/@href)"

MODULE_PROJECT_NAMES=("commons_prod" "bbf_prod" "inv_prod" "cash_prod")

# Clear openhmis module folder
mkdir -p ${DOWNLOAD_DIR}
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

# Cleanup temp files
rm -r /root/temp

fi

# Run tomcat
catalina.sh run