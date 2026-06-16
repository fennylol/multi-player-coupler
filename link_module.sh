#!/bin/bash

TARGETFILE=PingusPrime.gd
TARGETDIR=$(dirname "$0")
TARGET=$TARGETDIR/$TARGETFILE

if [[ -d $TARGETDIR ]]; then
   if [[ -f $TARGET ]]; then
      ln -s $TARGET .
   else
      echo ERROR: $TARGET not found
   fi
else
   echo ERROR: $TARGET not found
fi
