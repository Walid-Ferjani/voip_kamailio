FROM ubuntu:focal

ENV DEBIAN_FRONTEND=noninteractive

# Install updates and dependencies
RUN apt-get update && \
	apt-get -y install git vim wget subversion mysql-server

# Install Oracle Java 7 SE JDK
RUN mkdir -p  /usr/lib/jvm/ && \
	cd / && wget https://deb.digdeo.fr/java-archives/jdk-7u80-linux-x64.tar.gz && \
	tar -zxf /jdk-7u80-linux-x64.tar.gz -C /usr/lib/jvm/ && \
	update-alternatives --install /usr/bin/java java /usr/lib/jvm/jdk1.7.0_80/bin/java 100 && \
	update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/jdk1.7.0_80/bin/javac 100

# Install Ant
RUN cd / && wget http://archive.apache.org/dist/ant/binaries/apache-ant-1.9.14-bin.tar.gz && \
	tar xvfvz apache-ant-1.9.14-bin.tar.gz && \
	mv apache-ant-1.9.14 /usr/local/ && \
	ln -s /usr/local/apache-ant-1.9.14/bin/ant /usr/bin/ant

RUN mkdir -p /opt/OpenIMSCore && \
	cd /opt/OpenIMSCore && \
	git clone https://github.com/herlesupreeth/FHoSS

ENV JAVA_HOME="/usr/lib/jvm/jdk1.7.0_80"
ENV CLASSPATH="/usr/lib/jvm/jdk1.7.0_80/jre/lib/"
ENV ANT_HOME="/usr/local/apache-ant-1.9.14"
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN	cd /opt/OpenIMSCore/FHoSS && \
	ant compile deploy | tee ant_compile_deploy.txt

CMD /mnt/fhoss/fhoss_init.sh
