#!/bin/bash


mkdir /etc/kamailio_scscf
cp /mnt/scscf/scscf.cfg /etc/kamailio_scscf
cp /mnt/scscf/scscf.xml /etc/kamailio_scscf
cp /mnt/scscf/kamailio_scscf.cfg /etc/kamailio_scscf
cp /mnt/scscf/CxDataType_Rel6.xsd /etc/kamailio_scscf
cp /mnt/scscf/CxDataType_Rel7.xsd /etc/kamailio_scscf
cp /mnt/scscf/CxDataType_Rel8.xsd /etc/kamailio_scscf
cp /mnt/scscf/dispatcher.list /etc/kamailio_scscf

while ! mysqladmin ping -h ${MYSQL_IP} --silent; do
	sleep 5;
done

# Sleep until permissions are set
sleep 10;

# Create SCSCF database, populate tables and grant privileges
if [[ -z "`mysql -u root -h ${MYSQL_IP} -qfsBe "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='scscf'" 2>&1`" ]];
then
	mysql -u root -h ${MYSQL_IP} -e "create database scscf;"
	mysql -u root -h ${MYSQL_IP} scscf < /usr/local/src/kamailio/utils/kamctl/mysql/standard-create.sql
	mysql -u root -h ${MYSQL_IP} scscf < /usr/local/src/kamailio/utils/kamctl/mysql/presence-create.sql
	mysql -u root -h ${MYSQL_IP} scscf < /usr/local/src/kamailio/utils/kamctl/mysql/ims_usrloc_scscf-create.sql
	mysql -u root -h ${MYSQL_IP} scscf < /usr/local/src/kamailio/utils/kamctl/mysql/ims_dialog-create.sql
	mysql -u root -h ${MYSQL_IP} scscf < /usr/local/src/kamailio/utils/kamctl/mysql/ims_charging-create.sql
	SCSCF_USER_EXISTS=`mysql -u root -h ${MYSQL_IP} -s -N -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = 'scscf' AND Host = '%')"`
	if [[ "$SCSCF_USER_EXISTS" == 0 ]]
	then
		mysql -u root -h ${MYSQL_IP} -e "CREATE USER 'scscf'@'%' IDENTIFIED WITH mysql_native_password BY 'heslo'";
		mysql -u root -h ${MYSQL_IP} -e "CREATE USER 'scscf'@'$SCSCF_IP' IDENTIFIED WITH mysql_native_password BY 'heslo'";
		mysql -u root -h ${MYSQL_IP} -e "GRANT ALL ON scscf.* TO 'scscf'@'%'";
		mysql -u root -h ${MYSQL_IP} -e "GRANT ALL ON scscf.* TO 'scscf'@'$SCSCF_IP'";
		mysql -u root -h ${MYSQL_IP} -e "FLUSH PRIVILEGES;"
	fi
fi

export IMS_SLASH_DOMAIN=`echo $IMS_DOMAIN | sed 's/\./\\\./g'`

sed -i 's|SCSCF_IP|'$SCSCF_IP'|g' /etc/kamailio_scscf/scscf.cfg
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/kamailio_scscf/scscf.cfg
sed -i 's|IMS_SLASH_DOMAIN|'$IMS_SLASH_DOMAIN'|g' /etc/kamailio_scscf/scscf.cfg
sed -i 's|MYSQL_IP|'$MYSQL_IP'|g' /etc/kamailio_scscf/scscf.cfg

sed -i 's|SCSCF_IP|'$SCSCF_IP'|g' /etc/kamailio_scscf/scscf.xml
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/kamailio_scscf/scscf.xml

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
