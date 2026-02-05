#!/bin/bash



cp /mnt/fhoss/configurator.sh /opt/OpenIMSCore/FHoSS/deploy
cp /mnt/fhoss/DiameterPeerHSS.xml /opt/OpenIMSCore/FHoSS/deploy
cp /mnt/fhoss/hibernate.properties /opt/OpenIMSCore/FHoSS/deploy
cp /mnt/fhoss/configurator.sh /opt/OpenIMSCore/FHoSS/scripts
cp /mnt/fhoss/configurator.sh /opt/OpenIMSCore/FHoSS/config

cd /opt/OpenIMSCore/FHoSS/deploy && ./configurator.sh ${IMS_DOMAIN} ${FHOSS_IP}
sed -i 's|open-ims.org|'$IMS_DOMAIN'|g' /opt/OpenIMSCore/FHoSS/deploy/webapps/hss.web.console/WEB-INF/web.xml
sed -i 's|MYSQL_IP|'$MYSQL_IP'|g' /opt/OpenIMSCore/FHoSS/deploy/hibernate.properties
sed -i 's|FHOSS_IP|'$FHOSS_IP'|g' /opt/OpenIMSCore/FHoSS/deploy/DiameterPeerHSS.xml
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /opt/OpenIMSCore/FHoSS/deploy/DiameterPeerHSS.xml
cd /opt/OpenIMSCore/FHoSS/scripts && ./configurator.sh ${IMS_DOMAIN} ${FHOSS_IP}
cd /opt/OpenIMSCore/FHoSS/config && ./configurator.sh ${IMS_DOMAIN} ${FHOSS_IP}
sed -i 's|open-ims.org|'$IMS_DOMAIN'|g' /opt/OpenIMSCore/FHoSS/src-web/WEB-INF/web.xml

while ! mysqladmin ping -h ${MYSQL_IP} --silent; do
	sleep 5;
done

# Sleep until permissions are set
sleep 10;

# Create FHoSS database, populate tables and grant privileges
if [[ -z "`mysql -u root -h ${MYSQL_IP} -qfsBe "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='hss_db'" 2>&1`" ]];
then
	mysql -u root -h ${MYSQL_IP} -e "create database hss_db;"
	mysql -u root -h ${MYSQL_IP} hss_db < /opt/OpenIMSCore/FHoSS/scripts/hss_db.sql
	FHOSS_USER_EXISTS=`mysql -u root -h ${MYSQL_IP} -s -N -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = 'hss' AND Host = '%')"`
	if [[ "$FHOSS_USER_EXISTS" == 0 ]]
	then
		mysql -u root -h ${MYSQL_IP} -e "CREATE USER 'hss'@'%' IDENTIFIED WITH mysql_native_password BY 'hss'";
		mysql -u root -h ${MYSQL_IP} -e "CREATE USER 'hss'@'$FHOSS_IP' IDENTIFIED WITH mysql_native_password BY 'hss'";
		mysql -u root -h ${MYSQL_IP} -e "GRANT ALL ON hss_db.* TO 'hss'@'%'";
		mysql -u root -h ${MYSQL_IP} -e "GRANT ALL ON hss_db.* TO 'hss'@'$FHOSS_IP'";
		mysql -u root -h ${MYSQL_IP} -e "FLUSH PRIVILEGES;"
	fi
	mysql -u root -h ${MYSQL_IP} hss_db < /opt/OpenIMSCore/FHoSS/scripts/userdata.sql
fi

VIS_NET_PRESENT=`mysql -u root -h ${MYSQL_IP} hss_db -s -N -e "SELECT count(*) FROM visited_network;"`
if [[ "$VIS_NET_PRESENT" -gt 0 ]]
then
	mysql -u root -h ${MYSQL_IP} hss_db -e "DELETE FROM visited_network;"
	mysql -u root -h ${MYSQL_IP} hss_db -e "INSERT INTO visited_network VALUES (1, '$IMS_DOMAIN');"
fi

PREF_SCSCF_PRESENT=`mysql -u root -h ${MYSQL_IP} hss_db -s -N -e "SELECT count(*) FROM preferred_scscf_set;"`
if [[ "$PREF_SCSCF_PRESENT" -gt 0 ]]
then
	mysql -u root -h ${MYSQL_IP} hss_db -e "DELETE FROM preferred_scscf_set;"
	mysql -u root -h ${MYSQL_IP} hss_db -e "INSERT INTO preferred_scscf_set VALUES (1, 1, 'scscf1', 'sip:scscf.$IMS_DOMAIN:6060', 0);"
fi

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

echo "Configuring OpenSIPS presence server IP..."
OPENSIPS_AS_EXISTS=`mysql -u root -h ${MYSQL_IP} hss_db -s -N -e "SELECT count(*) FROM application_server WHERE name='default_as';"`
if [[ "$OPENSIPS_AS_EXISTS" -gt 0 ]]
then
	echo "Updating default_as to point to OpenSIPS at ${PRESENCE_IP}..."
	mysql -u root -h ${MYSQL_IP} hss_db -e "UPDATE application_server SET server_name='sip:${PRESENCE_IP}:5065' WHERE name='default_as';"
fi


cp /mnt/fhoss/hss.sh /
cd / && ./hss.sh
