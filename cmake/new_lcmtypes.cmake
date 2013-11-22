# Macros for automatically compiling LCM types into C, Java, and Python
# libraries.
#
# Defines the following macros/functions:
#
#     add_lcmtype(lcmfile)
#          which generates build rules for C,CPP, Java (if java is available), and 
#	   Python (if python is available) by calling the methods below
#
#     add_c_lcmtype(lcmfile)
#     add_cpp_lcmtype(lcmfile)
#     add_java_lcmtype(lcmfile)
#     add_python_lcmtype(lcmfile)
#
#  The following should be called AFTER all add_lcmtype calls:
#
#     lcmtypes_build([C_AGGREGATE_HEADER header_fname] 
#                    [C_LIBNAME lib_name]
#		     [CPP_AGGREGATE_HEADER header_fname]
#                    [JARNAME jar_name])
#
#          In addition to any files added via add_lcm calls, this function will 
#          search the variable ${LCMTYPES_SEARCHDIR} and automatically call
#          add_lcm() for all .lcm files in that directory.  For backwards 
#          compatibility, the default value is 
#             LCMTYPES_SEARCHDIR=CMAKE_SOURCE_DIR/lcmtypes
#          This has the drawback that new LCM files will not be added to the 
#          build until cmake runs again.  The recommended best practice is to
#          use add_lcmtype and not rely on the search, but manually calling
#             unset(LCMTYPES_SEARCHDIR)
#          after include(lcmtypes.cmake) and before lcmtypes_build.
#
#          After invoking this macro, the lcmtypes include directory will 
#          automatically be added, and the target variables will be set:
#             LCMTYPES_C_TARGET
#             LCMTYPES_C_LIBRARY
#             LCMTYPES_CPP_TARGET
#             LCMTYPES_JAVA_TARGET
#    
# C
# ==
# 
# The autogenerated C bindings get compiled to a static and shared library.  
# The library prefix will be stored in LCMTYPES_LIBS on output. This prefix 
# can be manually set using the C_LIBNAME option.
# 
# Additionally, a header file will be generated that automatically includes
# all of the other automatically generated header files.  The name of this
# header file defaults to a cleaned-up version of "${PROJECT_NAME}.h" 
# (non-alphanumeric characters replaced with underscores), but can
# be manually set using the C_AGGREGATE_HEADER option.
#
# C++
# ==
# 
# The autogenerated CPP bindings are header only, so no library is created.
# 
# A header file will be generated that automatically includes
# all of the other automatically generated header files.  The name of this
# header file defaults to a cleaned-up version of "${PROJECT_NAME}.hpp" 
# (non-alphanumeric characters replaced with underscores), but can
# be manually set using the CPP_AGGREGATE_HEADER option.
#
#
# Java
# ====
#
# Targets are added to automatically compile the .java files to a
# .jar file that will be installed to 
#   ${CMAKE_INSTALL_PREFIX}/share/java
# The location of this jar file is stored in LCMTYPES_JAR
#
# Python
# ======
#
# .py files will be installed to 
#   ${CMAKE_INSTALL_PREFIX}/lib/python{X.Y}/dist-packages
#   
# where {X.Y} refers to the python version used to build the .py files.
#
# ----
# File: lcmtypes.cmake
# Distributed with pods version: 12.09.21

cmake_minimum_required(VERSION 2.8.3) # for the CMakeParseArguments macro 

find_package(PkgConfig REQUIRED)
pkg_check_modules(LCM REQUIRED lcm)
    
#find lcm-gen (it may be in the install path)
find_program(LCM_GEN_EXECUTABLE lcm-gen ${EXECUTABLE_OUTPUT_PATH} ${EXECUTABLE_INSTALL_PATH})
  
if (NOT LCM_GEN_EXECUTABLE)
  message(FATAL_ERROR "lcm-gen not found!\n")
  return()
endif()

set(LCMTYPES_DIR ${CMAKE_CURRENT_BINARY_DIR}/lcmtypes)
execute_process(COMMAND mkdir -p ${LCMTYPES_DIR})
include_directories(${LCMTYPES_DIR})

set(LCMTYPES_SEARCHDIR ${CMAKE_SOURCE_DIR}/lcmtypes)

function(find_lcmtypes msgvar)
  # get a list of all LCM types and store it in msgvar
  file(GLOB __tmplcmtypes "${LCMTYPES_SEARCHDIR}/*.lcm")
  foreach(_msg ${__tmplcmtypes})
    # Try to filter out temporary and backup files
    if(${_msg} MATCHES "^[^\\.].*\\.lcm$")
      list(APPEND ${msgvar} ${_msg})
    endif(${_msg} MATCHES "^[^\\.].*\\.lcm$")
  endforeach(_msg)

  set(${msgvar} ${${msgvar}} PARENT_SCOPE)
endfunction()

macro(lcmtypes_build_c)
  find_lcmtypes(_msgs)
  foreach(_msg ${_msgs})
    add_c_lcmtype(${_msg})
  endforeach()

  cmake_parse_arguments("LCMTYPES" "" "C_AGGREGATE_HEADER;C_LIBNAME" "" ${ARGV})
  string(REGEX REPLACE "[^a-zA-Z0-9]" "_" __sanitized_project_name "${PROJECT_NAME}")

  if (NOT LCMTYPES_C_AGGREGATE_HEADER)
    set(LCMTYPES_C_AGGREGATE_HEADER "${__sanitized_project_name}.h")
  endif()
  if (NOT LCMTYPES_C_LIBNAME)
    set(LCMTYPES_C_LIBNAME "${__sanitized_project_name}_lcmtypes")
  endif()

  if (LCMTYPES_C_SOURCEFILES)
    list(REMOVE_DUPLICATES LCMTYPES_C_SOURCEFILES)
    add_library(${LCMTYPES_C_LIBNAME} ${LCMTYPES_C_SOURCEFILES})

    # create a header file aggregating all of the autogenerated .h files
    set(__agg_h_fname "${LCMTYPES_DIR}/${__sanitized_project_name}.h")
    set(__h_str "#ifndef __lcmtypes_${__sanitized_project_name}_h__\\n#define __lcmtypes_${__sanitized_project_name}_h__\\n\\n")
    foreach(c_file ${LCMTYPES_C_SOURCEFILES})
      string(REGEX REPLACE ".c$" ".h" h_file ${c_file})
      file(RELATIVE_PATH __tmp_path ${LCMTYPES_DIR} ${h_file})
      set(__h_str "${__h_str}#include \"${__tmp_path}\"\\n")
      get_filename_component(__tmp_dir ${__tmp_path} PATH)
      install(FILES ${h_file} DESTINATION "include/lcmtypes/${__tmp_dir}")
    endforeach()
    set(__h_str "${__h_str}\\n#endif\\n")

    add_custom_command(OUTPUT ${__agg_h_fname}
      COMMAND echo "${__h_str}" ">" "${__agg_h_fname}"  
      DEPENDS ${LCMTYPES_CPP_SOURCEFILES}
      VERBATIM
    )

    # add a custom target to force generation of aggregate h file
    add_custom_target(lcmtype_agg_h ALL
      DEPENDS ${__agg_h_fname})

    pods_install_libraries(${LCMTYPES_C_LIBNAME})
    install(FILES ${__agg_h_fname} DESTINATION lcmtypes)

    unset(__h_str)
    unset(__agg_h_fname)

  endif()

  set(LCMTYPES_C_TARGET lcmtype_agg_h ${LCMTYPES_C_LIBNAME})
  set(LCMTYPES_C_LIBRARY ${LCMTYPES_C_LIBNAME})
endmacro()

macro(lcmtypes_build_cpp)
  find_lcmtypes(_msgs)
  foreach(_msg ${_msgs})
    add_cpp_lcmtype(${_msg})
  endforeach()

  cmake_parse_arguments("LCMTYPES" "" "CPP_AGGREGATE_HEADER" "" ${ARGV})
  string(REGEX REPLACE "[^a-zA-Z0-9]" "_" __sanitized_project_name "${PROJECT_NAME}")

  if (NOT LCMTYPES_CPP_AGGREGATE_HEADER)
    set(LCMTYPES_C_AGGREGATE_HEADER "${__sanitized_project_name}.hpp")
  endif()

  if (LCMTYPES_CPP_HEADERFILES)
    list(REMOVE_DUPLICATES LCMTYPES_CPP_HEADERFILES)

    # create a header file aggregating all of the autogenerated .hpp files
    set(__agg_hpp_fname "${LCMTYPES_DIR}/${__sanitized_project_name}.hpp")
    set(__hpp_str "#ifndef __lcmtypes_${__sanitized_project_name}_hpp__\\n#define __lcmtypes_${__sanitized_project_name}_hpp__\\n\\n")
    foreach(hpp_file ${LCMTYPES_CPP_HEADERFILES})
      file(RELATIVE_PATH __tmp_path ${LCMTYPES_DIR} ${hpp_file})
      set(__hpp_str "${__hpp_str}#include \"${__tmp_path}\"\\n")
      get_filename_component(__tmp_dir ${__tmp_path} PATH)
      install(FILES ${hpp_file} DESTINATION "include/lcmtypes/${__tmp_dir}")
    endforeach()
    set(__hpp_str "${__hpp_str}\\n#endif\\n")

    add_custom_command(OUTPUT ${__agg_hpp_fname}
      COMMAND echo "${__hpp_str}" ">" "${__agg_hpp_fname}"
      DEPENDS ${LCMTYPES_CPP_HEADERFILES}
      VERBATIM
    )

    # add a custom target to force generation of aggregate hpp
    add_custom_target(lcmtype_agg_hpp ALL
      DEPENDS ${__agg_hpp_fname})

    install(FILES ${__agg_hpp_fname} DESTINATION lcmtypes)
    unset(__hpp_str)
    unset(__agg_hpp_fname)

  endif()

  set(LCMTYPES_CPP_TARGET lcmtype_agg_hpp)
endmacro()

macro(lcmtypes_build_java)
  find_lcmtypes(_msgs)
  foreach(_msg ${_msgs})
    add_java_lcmtype(${_msg})
  endforeach()

  cmake_parse_arguments("LCMTYPES" "" "JARNAME" "" ${ARGV})
  string(REGEX REPLACE "[^a-zA-Z0-9]" "_" __sanitized_project_name "${PROJECT_NAME}")

  if (NOT LCMTYPES_JARNAME)
    set(LCMTYPES_JARNAME "lcmtypes_${__sanitized_project_name}")
  endif()

  if (LCMTYPES_JAVA_SOURCEFILES)
    list(REMOVE_DUPLICATES LCMTYPES_JAVA_SOURCEFILES)

    find_package(Java REQUIRED)
    include(UseJava)

    pods_use_pkg_config_classpath(lcm-java)

    add_jar(${LCMTYPES_JARNAME} ${LCMTYPES_JAVA_SOURCEFILES})

    pods_install_pkg_config_file(lcmtypes_${PROJECT_NAME}-java
    	CLASSPATH ${LCMTYPES_JARNAME}
    	DESCRIPTION "LCM type java bindings for ${PROJECT_NAME}"
    	REQUIRES lcm-java
    	VERSION 0.0.0)
  endif()

  set(LCMTYPES_JAVA_TARGET ${LCMTYPES_JARNAME})
endmacro()


macro(lcmtypes_build)

  lcmtypes_build_c(${ARGV})

  lcmtypes_build_cpp(${ARGV})

  lcmtypes_build_java(${ARGV})

#  todo: handle python

endmacro()

function(lcmgen)
  execute_process(COMMAND ${LCM_GEN_EXECUTABLE} ${ARGV} RESULT_VARIABLE lcmgen_result)
  if(NOT lcmgen_result EQUAL 0)
    message(FATAL_ERROR "lcm-gen failed")
  endif()
endfunction()

macro(get_package_name lcmtype)
  # extract package name from lcm file.  
  # creates variable ${_package_name}
  # todo: make this more robust

  execute_process(COMMAND sed -n -e "s/^.*package *\\(.*\\); *$/\\1/p" "${lcmtype}" OUTPUT_VARIABLE _package_name OUTPUT_STRIP_TRAILING_WHITESPACE)
endmacro()

function(add_c_lcmtype lcmtype)
  get_filename_component(lcmtype ${lcmtype} ABSOLUTE)
  get_filename_component(lcmtype_we ${lcmtype} NAME_WE)
  get_package_name(${lcmtype})
  if (_package_name)
    string(REPLACE "." "_" package_prefix "${_package_name}")
    set(package_prefix "${package_prefix}_")
  endif()
  set(lcmtype_w_package "${package_prefix}${lcmtype_we}")

  add_custom_command(OUTPUT "${LCMTYPES_DIR}/${lcmtype_w_package}.c" "${LCMTYPES_DIR}/${lcmtype_w_package}.h" PRE_LINK
  		     COMMAND "${LCM_GEN_EXECUTABLE}" --c "${lcmtype}"
		     DEPENDS ${lcmtype}
		     WORKING_DIRECTORY ${LCMTYPES_DIR})
  set(LCMTYPES_C_SOURCEFILES ${LCMTYPES_C_SOURCEFILES} "${LCMTYPES_DIR}/${lcmtype_w_package}.c" PARENT_SCOPE)

endfunction()

function(add_cpp_lcmtype lcmtype)
  get_filename_component(lcmtype ${lcmtype} ABSOLUTE)
  get_filename_component(lcmtype_we ${lcmtype} NAME_WE)
  get_package_name(${lcmtype})
  if (_package_name)
    string(REPLACE "." "/" package_prefix "${_package_name}")
    set(package_prefix "${package_prefix}/")
  endif()
  set(lcmtype_w_package "${package_prefix}${lcmtype_we}")

  add_custom_command(OUTPUT "${LCMTYPES_DIR}/${lcmtype_w_package}.hpp" 
  		     COMMAND "${LCM_GEN_EXECUTABLE}" --cpp "${lcmtype}"
		     DEPENDS ${lcmtype}
		     WORKING_DIRECTORY ${LCMTYPES_DIR})
  set(LCMTYPES_CPP_HEADERFILES ${LCMTYPES_CPP_HEADERFILES} "${LCMTYPES_DIR}/${lcmtype_w_package}.hpp" PARENT_SCOPE)

endfunction()

function(add_java_lcmtype lcmtype)
  get_filename_component(lcmtype ${lcmtype} ABSOLUTE)
  get_filename_component(lcmtype_we ${lcmtype} NAME_WE)
  get_package_name(${lcmtype})
  if (_package_name)
    string(REPLACE "." "/" package_prefix "${_package_name}")
    set(package_prefix "${package_prefix}/")
  endif()
  set(lcmtype_w_package "${package_prefix}${lcmtype_we}")

  add_custom_command(OUTPUT "${LCMTYPES_DIR}/${lcmtype_w_package}.java" PRE_LINK
  		     COMMAND "${LCM_GEN_EXECUTABLE}" --java "${lcmtype}"
		     DEPENDS ${lcmtype}
		     WORKING_DIRECTORY ${LCMTYPES_DIR})
  set(LCMTYPES_JAVA_SOURCEFILES ${LCMTYPES_JAVA_SOURCEFILES} "${LCMTYPES_DIR}/${lcmtype_w_package}.java" PARENT_SCOPE)

endfunction()

function(add_lcmtype)
  add_c_lcmtype(${ARGV})
  set(LCMTYPES_C_SOURCEFILES ${LCMTYPES_C_SOURCEFILES} PARENT_SCOPE)

  add_cpp_lcmtype(${ARGV})
  set(LCMTYPES_CPP_HEADERFILES ${LCMTYPES_CPP_HEADERFILES} PARENT_SCOPE)
  
  add_java_lcmtype(${ARGV})
  set(LCMTYPES_JAVA_SOURCEFILES ${LCMTYPES_JAVA_SOURCEFILES} PARENT_SCOPE)

# todo: handle python
#  add_python_lcmtype(${ARGV})
endfunction()

