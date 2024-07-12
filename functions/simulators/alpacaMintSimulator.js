const {simulateScript, decodeResult}  = require("@chainlink/functions-toolkit");
const requestConfig = require("../configs/alpacaMintConfig")
async function main(){
    const {responseBytesHexstring, errorString, capturedTerminalOutput} = await simulateScript(requestConfig)

    if(responseBytesHexstring)
    {
        console.log(`Response returned by script: ${decodeResult(
            responseBytesHexstring, requestConfig.expectedReturnType
        ).toString()}\n`)
    }
    if(errorString)
    {
        console.log(`Error returned by scrip: ${errorString}\n`);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
})