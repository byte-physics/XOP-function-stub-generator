#!/bin/sh

set -e

version=0.15

git archive -o releases/xop-stub-generator-${version}.zip xop-stub-generator-${version} .
zip -qju releases/xop-stub-generator-${version}.zip function*

git add releases/*
git commit -m "xop-stub-generator.pl: Add new release" releases
