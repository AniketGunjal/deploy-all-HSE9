#!/bin/sh

#echo "Update keycloak admin account details"

_accessTokenUrl="$_keycloakAddr/auth/realms/master/protocol/openid-connect/token"
_adminCliClientUrl="$_keycloakAddr/auth/admin/realms/master/clients?clientId=admin-cli"
_adminUserUrl="$_keycloakAddr/auth/admin/realms/master/users"

#Function to fetch Access Token from keycloak
getAccessToken() {
    curl -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "client_id=admin-cli&username=Administrator&password=centric8&grant_type=password" \
    "$_accessTokenUrl" | grep -o '"access_token":"[^"]*"' | grep -o '"[^"]*"$' | sed -e 's/^"//' -e 's/"$//'
}

#Function to fetch the admin user id
getAdminUserId() {
    curl --request GET --url "$_adminUserUrl" -H "Authorization: Bearer $(getAccessToken)" | grep -o '"id":"[^"]*"' | grep -o '"[^"]*"$' | sed -e 's/^"//' -e 's/"$//'
}

#Function to fetch the admin-cli client id for automating client role updates
fetchAdminCliId() {
    curl --request GET --url "$_adminCliClientUrl" -H "Authorization: Bearer $(getAccessToken)" | grep -o '"id":"[^"]*"' | grep -o '"[^"]*"$' | sed -e 's/^"//' -e 's/"$//'
}

_updateAdminCliClientRolesUrl="$_keycloakAddr/auth/admin/realms/master/clients/$(fetchAdminCliId)/roles"
_updateKeycloakAdminAccountDetailsUrl="$_keycloakAddr/auth/admin/realms/master/users/$(getAdminUserId)"

#Function to add 'realm-admin' role to the admin-cli client without which we cannot perform updateKeycloakAdminAccountDetails
updateAdminCliClientRoles() {
    curl -X POST \
            -H 'Content-Type: application/json' \
            -H "grant_type: $_granttype" \
            -H "client_id: $_clientId" \
            -H "username: $_username" \
            -H "password: $_password" \
            -H "Authorization: Bearer $(getAccessToken)" \
            -H 'Connection: keep-alive' \
            -H 'Accept: */*' \
            -H 'Accept-Encoding: gzip, deflate, br' \
            --data "{\"name\":\"$_role\",\"composite\":\"$_composite\",\"clientRole\":\"$_clientRole\"}" \
            "$_updateAdminCliClientRolesUrl"
}

#Function to update the keycloak admin account details
updateKeycloakAdminAccountDetails() {
    curl -X PUT \
            -H 'Content-Type: application/json' \
            -H "grant_type: $_granttype" \
            -H "client_id: $_clientId" \
            -H "username: $_username" \
            -H "password: $_password" \
            -H "Authorization: Bearer $(getAccessToken)" \
            -H 'Connection: keep-alive' \
            -H 'Accept: */*' \
            -H 'Accept-Encoding: gzip, deflate, br' \
            --data "{\"firstName\":\"$_firstName\",\"lastName\":\"$_lastName\",\"email\":\"$_email\"}" \
            "$_updateKeycloakAdminAccountDetailsUrl"
}

#Calling function to update client roles
updateAdminCliClientRoles
#Calling function to update admin details
updateKeycloakAdminAccountDetails