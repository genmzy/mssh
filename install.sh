#!/bin/sh

set -x

if [ -e /usr/bin/dpkg ]; then
	echo "debain-serial system, use apt-get now"
	sudo apt-get -y install expect
else
	if [ -e /usr/bin/rpm ]; then
		echo "red-hat-serial system, use yum now"
		sudo yum -y install expect
	else
		echo "not supported system type, only support yum or apt-get package manager now, quiting ..."
		exit 1
	fi
fi

if [ $? -ne 0 ]; then
	echo "some error happened, quiting now"
	exit 1
fi

sudo cp ./ms /usr/local/bin/
mkdir "$HOME"/.config/

echo "first trying and generate configuration sample"

ms
