#!/usr/bin/env bash
echo "Running tests with simple redis"
make test-docker-jenkins
while docker ps | grep test_gateway_1  ; do
    echo "Waiting for tests to finish"
    sleep 5
done
echo "Finished integration tests"
if ! docker logs test_gateway_1 --tail 1 | grep "PASS" ; then
    echo "FAILED TESTS"
    docker logs test_gateway_1
    cd ./tests && docker-compose stop && docker-compose rm -f
    exit 64
fi
docker logs test_gateway_1 --tail 1
cd ./test && docker-compose -f docker-compose-jenkins.yml stop && docker-compose -f docker-compose-jenkins.yml rm -fk
rm -rf  ~/tmp/apiplatform/api-gateway-request-validation
cd ../

echo "Running tests with redis with password"

make test-docker-with-password-jenkins
while docker ps | grep test_gateway_1  ; do
    echo "Waiting for tests to finish"
    sleep 5
done
echo "Finished integration tests"
if ! docker logs test_gateway_1 --tail 1 | grep "PASS" ; then
    echo "FAILED TESTS"
    docker logs test_gateway_1
    cd ./tests && docker-compose stop && docker-compose rm -f
    exit 64
fi
docker logs test_gateway_1 --tail 1
cd ./test && docker-compose -f docker-compose-with-password-jenkins.yml stop && docker-compose -f docker-compose-with-password-jenkins.yml rm -f
rm -rf  ~/tmp/apiplatform/api-gateway-request-validation
cd ../