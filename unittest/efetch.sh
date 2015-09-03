#!/usr/bin/env bash

ETEST_efetch_md5_bogus()
{
    local tmpfile=$(mktemp /tmp/etest-efetch-XXXX)
    touch ${tmpfile}.md5

    # efetch should fail b/c this isn't a valid MD5 file
    ! efetch -m file://${tmpfile}
}

ETEST_efetch_md5()
{
    # Create a temporary file
    local tmpfile=$(mktemp /tmp/etest-efetch-XXXX)
    dd if=/dev/urandom of=${tmpfile} bs=1M count=2
    emd5sum ${tmpfile} > ${tmpfile}.md5

    efetch -m file://${tmpfile} copy.txt
    [[ -e copy.txt ]]
    [[ -e copy.txt.md5 ]]
    diff ${tmpfile} copy.txt
}

ETEST_efetch_md5_missing_md5()
{
    # Create a temporary file
    local tmpfile=$(mktemp /tmp/etest-efetch-XXXX)
    dd if=/dev/urandom of=${tmpfile} bs=1M count=2

    # efetch should fail and both files should get removed
    ! efetch -m file://${tmpfile} copy.txt
    [[ ! -e copy.txt ]]
    [[ ! -e copy.txt.md5 ]]
}

ETEST_efetch_md5_missing_file()
{
    # Create a temporary file
    local tmpfile=$(mktemp /tmp/etest-efetch-XXXX.md5)

    # efetch should fail and both files should get removed
    ! efetch -m file://${tmpfile%%.md5} copy.txt
    [[ ! -e copy.txt ]]
    [[ ! -e copy.txt.md5 ]]
}

ETEST_efetch_meta()
{
    # Create a temporary file
    local tmpfile=$(mktemp /tmp/etest-efetch-XXXX)
    dd if=/dev/urandom of=${tmpfile} bs=1M count=2
    echecksum ${tmpfile} > ${tmpfile}.meta
    echecksum_check ${tmpfile}

    efetch -M file://${tmpfile} copy.txt
    [[ -e copy.txt ]]
    [[ -e copy.txt.meta ]]
    diff ${tmpfile} copy.txt

    echecksum_check copy.txt
}
 
