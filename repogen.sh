#!/bin/sh

#------------------------------------------------------------------------------
#
# Copyright (c) 2017 Dinesh Thirumurthy <dinesh.thirumurthy@gmail.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
#------------------------------------------------------------------------------

set -x

# Usage:
# repogen.sh -	will mirror an OpenBSD CVS mirror
#		convert the cvs repo to bare git repos of src,xenocara,ports and www
#		create typical git repos of the bare git repos
#
#		when repeated, will update all of above with latest code 
#
#		user should aim it a particular openbsd rsync mirror 
#		and run it regularly to maintain updated git mirrors
#
# Steps:
# $ doas pkg_add git
# $ doas pkg_add cvs2gitdump
# $ doas pkg_add rsync
# $ mkdir repo
# $ cd repo
# $ git clone https://github.com/hakrtech/repogen.git
# $ chmod +x repogen/repogen.sh 
# $ ./repogen/repogen.sh
# will generate 
# 1.	cvsrepo0/	- cvs repository mirrored from france
# 2.	bare.src.git/	- bare git repository of src module of cvs repo
# 3.	bare.xenocara.git/	- same for xenocara
# 4.	bare.ports.git/	- same for ports
# 5.	bare.www.git/	- same for www
# 6.	src0/		- checkout of master from bare repository for src
# 7.	xenocara0/	- same for xenocara
# 8.	ports0/		- same for ports
# 9.	www0/		- same for www
# 10.   push.src0	- clone of src0, used to push to github
#
# and you run it again to update all of above i.e. 
# $ ./repogen/repogen.sh
# will update
# 1.	cvsrepo0/	- update cvs repository mirrored from france
# 2.	bare.src.git/	- update bare git repository of src module of cvs repo
# 3.	bare.xenocara.git/	- update same for xenocara
# 4.	bare.ports.git/	- update same for ports
# 5.	bare.www.git/	- update same for www
# 6.	src0/		- update checkout of master from bare repository for src
# 7.	xenocara0/	- update same for xenocara
# 8.	ports0/		- update same for ports
# 9.	www0/		- update same for www
# 10.   push.src0	- update clone of src0, and then push to github

rsynchostpath=anoncvs.fr.openbsd.org/openbsd-cvs/
upsync=1 # rsync with upstream mirror 
githubreporoot=""

# if set push to this github repository, you should have set up ssh key based access to 
# your github account and you should be assigned write permissions to this repository
# of course, this repository should exist in the first place
# uncomment if needed and change to your repository
# githubreporoot="git@github.com:hakrtech"

mark() { 
	echo -n "MARK "; date
}

require() {
	binpath=/usr/local/bin/$binfile
	if [ ! -x $binpath ]; then
		echo "$0: error cannot run without $binpath, install it"
		exit 1
	fi
}

for binfile in rsync git cvs2gitdump
do
	require $binfile
done
cvs2gitdump=/usr/local/bin/cvs2gitdump

mark

# incoming cvs repository - cvsrepo0
cvsrepo=`pwd`/cvsrepo0
echo "MARK cvsrepo is $cvsrepo"
if [ $upsync -eq 1 ]; then
	mark
	/usr/local/bin/rsync -az --delete rsync://$rsynchostpath $cvsrepo
	mark
fi

if [ -e /cvs ]; then
	cvsrepo=/cvs
fi

savedir=`pwd`
run=""
run2=""

for module in xenocara ports www src
do
	cd $savedir
	repodir=bare.${module}.git
	baregitrepo=`pwd`/bare.${module}.git
	workgitrepo="${module}0"
	mark
	if [ ! -d $baregitrepo ]; then
		$run git init --bare $baregitrepo
		$run $cvs2gitdump -k OpenBSD -e openbsd.org $cvsrepo/$module | \
			$run git --git-dir $baregitrepo fast-import
		# create non bare git (typical) git repo from bare repo
		$run /bin/rm -f $workgitrepo
	else
		$run $cvs2gitdump -k OpenBSD -e openbsd.org $cvsrepo/$module $baregitrepo | \
			$run git --git-dir $baregitrepo fast-import
		# update non bare git repo (typical) from bare repo
	fi
	mark
	if [ ! -d $workgitrepo ]; then
		$run2 git clone $baregitrepo $workgitrepo
	fi
	mark
	cd $workgitrepo && $run2 git pull && cd ..
	mark

	if [ $githubreporoot != "" ]; then
		githubrepo="$githubreporoot/openbsd-${module}0-test.git"
		cwd=`pwd`
		pushrepo="$cwd/push.${module}0"
		echo $pushrepo
		if [ ! -d $pushrepo ]; then
			git clone $workgitrepo $pushrepo
		fi
		if [ -d $pushrepo ]; then
			cd $pushrepo && git pull
			present=`cd $pushrepo && git remote -v | awk '{ if ($1 == "github") print $2; }' | wc -l`
			if [ $present -eq 0 ]; then
				cd $pushrepo && git remote add github $githubrepo
			fi
			present=`cd $pushrepo && git remote -v | awk '{ if ($1 == "github") print $2; }' | wc -l`
			if [ $present -ne 2 ]; then
				echo $0: unable to set git remote add $githubrepo
				exit 1
			fi
			git push --mirror --repo=$pushrepo github
		fi
	fi
done

