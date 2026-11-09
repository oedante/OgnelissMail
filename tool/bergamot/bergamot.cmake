# Ogneliss Mail: движок перевода Bergamot для Windows (2.2.0).
#
# Подключается одной строкой в конце windows/CMakeLists.txt (папку windows\
# создаёт flutter create — правят её .github/workflows/ci.yml и
# scripts/build_windows.ps1). Файлы движка кладёт в build/bergamot
# tool/bergamot/fetch_engine.sh (или .ps1) — отсюда при установке сборки они
# попадают рядом с exe, в data\bergamot. Проверка — при установке, а не при
# настройке CMake: движок, скачанный после первой сборки, тоже попадёт.
# Нет файлов — сборка без перевода (как до 2.2.0).
set(OGN_BERGAMOT_SRC "${CMAKE_CURRENT_LIST_DIR}/../../build/bergamot")
install(CODE "
  if(EXISTS \"${OGN_BERGAMOT_SRC}/translator.js\")
    file(INSTALL \"${OGN_BERGAMOT_SRC}\" DESTINATION \"${INSTALL_BUNDLE_DATA_DIR}\")
  else()
    message(STATUS \"Bergamot: ${OGN_BERGAMOT_SRC} not found, building without translation\")
  endif()
" COMPONENT Runtime)
