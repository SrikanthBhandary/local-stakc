import {
    CognitoIdentityProviderClient,
    InitiateAuthCommand
} from "@aws-sdk/client-cognito-identity-provider";

import config from "../config";

const client = new CognitoIdentityProviderClient({
    region: config.region,
    endpoint: config.cognitoEndpoint
});

const ACCESS_TOKEN = "accessToken";
const ID_TOKEN = "idToken";
const REFRESH_TOKEN = "refreshToken";

export async function login(username, password) {

    const response = await client.send(
        new InitiateAuthCommand({

            ClientId: config.clientId,

            AuthFlow: "USER_PASSWORD_AUTH",

            AuthParameters: {

                USERNAME: username,

                PASSWORD: password
            }
        })
    );

    if (!response.AuthenticationResult) {
        throw new Error("Authentication failed.");
    }

    const auth = response.AuthenticationResult;

    localStorage.setItem(
        ACCESS_TOKEN,
        auth.AccessToken
    );

    localStorage.setItem(
        ID_TOKEN,
        auth.IdToken
    );

    localStorage.setItem(
        REFRESH_TOKEN,
        auth.RefreshToken
    );

    return auth;
}

export function logout() {

    localStorage.removeItem(ACCESS_TOKEN);
    localStorage.removeItem(ID_TOKEN);
    localStorage.removeItem(REFRESH_TOKEN);

}

export function getAccessToken() {
    return localStorage.getItem(ACCESS_TOKEN);
}

export function getIdToken() {
    return localStorage.getItem(ID_TOKEN);
}

export function getRefreshToken() {
    return localStorage.getItem(REFRESH_TOKEN);
}

export function isAuthenticated() {

    return !!getAccessToken();

}

export async function refreshAccessToken() {

    const refreshToken = getRefreshToken();

    if (!refreshToken) {
        throw new Error("No refresh token found.");
    }

    const response = await client.send(
        new InitiateAuthCommand({

            ClientId: config.clientId,

            AuthFlow: "REFRESH_TOKEN_AUTH",

            AuthParameters: {

                REFRESH_TOKEN: refreshToken

            }

        })
    );

    const auth = response.AuthenticationResult;

    localStorage.setItem(
        ACCESS_TOKEN,
        auth.AccessToken
    );

    localStorage.setItem(
        ID_TOKEN,
        auth.IdToken
    );

    return auth.AccessToken;
}