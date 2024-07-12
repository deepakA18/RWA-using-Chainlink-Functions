if (secrets.alpacaKey == "" || secrets.alpacaSecret == "") {
    throw Error("Need alpaca key");
}

const alpacaRequest = Functions.makeHttpRequest({
    url: "https://paper-api.alpaca.markets/v2/account",
    headers: {
        accept: "application/json",
        'APCA-API-KEY-ID': secrets.alpacaKey,
        'APCA-API-SECRET-KEY': secrets.alpacaSecret
    }
});

const response = await Promise.all([alpacaRequest]);

// Log the entire response to understand its structure
console.log(JSON.stringify(response, null, 2));

// Since Promise.all returns an array, you need to access the first element
const responseData = response[0].data;

if (!responseData) {
    throw new Error("No data received from Alpaca API");
}

if (!responseData.portfolio_value) {
    throw new Error("portfolio_value is undefined in the response");
}

const portfolioBalance = responseData.portfolio_value;
console.log(`Alpaca Portfolio Balance: $${portfolioBalance}`);

return Functions.encodeUint256(Math.round(portfolioBalance * 100));
