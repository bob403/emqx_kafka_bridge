PROJECT = emqx_kafka_bridge
PROJECT_DESCRIPTION = EMQX Kafka Bridge
PROJECT_VERSION = 3.0

DEPS = ekaf
dep_ekaf = git https://github.com/helpshift/ekaf master


BUILD_DEPS = emqx cuttlefish
dep_emqx = git https://github.com/emqx/emqx emqx30
dep_cuttlefish = git https://github.com/emqx/cuttlefish emqx30

COVER = true

ERLC_OPTS += +debug_info
ERLC_OPTS += +'{parse_transform, lager_transform}'
TEST_ERLC_OPTS += +'{parse_transform, lager_transform}'

include erlang.mk

app:: rebar.config

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emqx_kafka_bridge.conf -i priv/emqx_kafka_bridge.schema -d data

