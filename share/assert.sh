#!/bin/bash
#
# Copyright 2016, SolidFire, Inc. All rights reserved.


# Executes a command (simply type the command after assert as if you were
# running it without assert) and calls die if that command returns a bad exit
# code.
#
# For example:
#    assert test 0 -eq 1
#
# There's a subtlety here that I don't think can easily be fixed given bash's
# semantics.  All of the arguments get evaluated prior to assert ever seeing
# them.  So it doesn't know what variables you passed in to an expression, just
# what the expression was.  This is pretty handy in cases like this one:
#
#   a=1
#   b=2
#   assert test "${a}" -eq "${b}"
#
# because assert will tell you that the command that it executed was 
#
#     test 1 -eq 2
#
# There it seems ideal.  But if you have an empty variable, things get a bit
# annoying.  For instance, this command will blow up because inside assert bash
# will try to evaluate [[ -z ]] without any arguments to -z.  (Note -- it still
# blows up, just not in quite the way you'd expect)
#
#    empty=""
#    assert test -z ${empty}
#
# To make this particular case easier to deal with, we also have assert_empty
# which you could use like this:
#
#    assert_empty empty
#
#
# IMPLEMENTATION NOTE: This doesn't work with bash double-bracket expressions.  Use test instead.
# To the best of my (Odell) understanding (as of 2016-07-01) bash must treat [[ ]] syntax specially.
# The problem is that we have two options for trying to run what is passed in to assert.
#
#     1) Pass it through eval, which will drop one more layer of quoting that we'd normally expect
#        (because it already dropped 1 layer of quoting when assert was called)
#     2) Just execute the command as something inside an array.  For instance, we could run it like
#        this
#           "${cmd[@]"
#        It works great for most commands, but blows up complaining that [[ isn't known as a valid
#        command.  Perhaps you can't run builtins in this manner?  Or at the very least you can't
#        run [[.
#
assert()
{
    "${@}"
}

assert_true()
{
    "${@}"
}

assert_false()
{
    local cmd=( "${@}" )
    
    local rc=0
    try
    {
        "${cmd[@]}"
    }
    catch
    {
        rc=$?
    }
    [[ ${rc} -ne 0 ]] || die "assert failed (rc=${rc}) :: ${cmd[@]}"
}

assert_op()
{
    compare "${@}" || "assert_op failed :: ${@}"
}

assert_eq()
{
    $(opt_parse "?lh" "?rh" "?msg")
    [[ "${lh}" == "${rh}" ]] || die "assert_eq failed [${msg:-}] :: $(lval lh rh)"
}

assert_ne()
{
    $(opt_parse "?lh" "?rh" "?msg")
    [[ ! "${lh}" == "${rh}" ]] || die "assert_ne failed [${msg:-}] :: $(lval lh rh)"
}

assert_match()
{
    $(opt_parse "?text" "?regex" "?msg")
    [[ "${text}" =~ ${regex} ]] || die "assert_match failed [${msg:-}] :: $(lval text regex)"
}

assert_not_match()
{
    $(opt_parse "?lh" "?rh" "?msg")
    [[ ! "${lh}" =~ "${rh}" ]] || die "assert_not_match failed [${msg:-}] :: $(lval lh rh)"
}

assert_zero()
{
    [[ ${1:-0} -eq 0 ]] || die "assert_zero received $1 instead of zero."
}

assert_not_zero()
{
    [[ ${1:-1} -ne 0 ]] || die "assert_not_zero received ${1}."
}

opt_usage assert_empty<<'END'
All arguments passed to assert_empty must be empty strings or else it will die and display the first
that is not.
END
assert_empty()
{
    local _arg
    for _arg in "$@" ; do
        [[ -z "${_arg}" ]] || die "${FUNCNAME} received $(lval _arg)"
    done
}

opt_usage assert_not_empty<<'END'
All arguments passed to assert_not_empty must be non-empty strings or else it will die and display
the first that is not.
END
assert_not_empty()
{
    local _arg
    for _arg in "$@" ; do
        [[ -n ${_arg} ]] || die "${FUNCNAME} received $(lval _arg)"
    done
}

opt_usage assert_var_empty<<'END'
Accepts variable names as parameters.  All passed in variable names must be either unset or must
contain only an empty string.

Note: there is not an analogue assert_var_not_empty.  Use argcheck instead.
END
assert_var_empty()
{
    local _arg
    for _arg in "$@" ; do
        [[ "${!_arg:-}" == "" ]] || die "${FUNCNAME} received $(lval _arg)"
    done
}

opt_usage assert_exists<<'END'
Accepts any number of filenames.  Blows up if any of the named files do not exist.
END
assert_exists()
{
    local name
    for name in "${@}"; do
        [[ -e "${name}" ]] || die "'${name}' does not exist"
    done
}

opt_usage assert_exists<<'END'
Accepts any number of filenames.  Blows up if any of the named files exist.
END
assert_not_exists()
{
    local name
    for name in "${@}"; do
        [[ ! -e "${name}" ]] || die "'${name}' exists"
    done
}

assert_archive_contents()
{
    $(opt_parse archive)
    edebug "Validating $(lval archive)"
    
    local expect=( "${@}" )
    array_sort expect

    assert_exists "${archive}"
    local actual=( $(archive_list ${archive}) )

    edebug "$(lval expect)"
    edebug "$(lval actual)"

    assert_eq "${#expect[@]}" "${#actual[@]}" "Size mismatch"

    local idx
    for idx in $(array_indexes expect); do
        eval "local e=\${expect[$idx]}"
        eval "local a=\${actual[$idx]}"

        assert_eq "${e}" "${a}" "Mismatch at index=${idx}"
    done
}

assert_directory_contents()
{
    $(opt_parse directory)
    edebug "Validating $(lval directory)"

    local expect=( "${@}" )
    array_sort expect
    
    assert_exists "${directory}"
    local actual=( $(find "${directory}" -printf '%P\n' | sort) )

    edebug "$(lval expect)"
    edebug "$(lval actual)"

    assert_eq "${#expect[@]}" "${#actual[@]}" "Size mismatch"

    local idx
    for idx in $(array_indexes expect); do
        eval "local e=\${expect[$idx]}"
        eval "local a=\${actual[$idx]}"

        assert_eq "${e}" "${a}" "Mismatch at index=${idx}"
    done
}

