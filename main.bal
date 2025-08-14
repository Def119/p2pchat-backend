// import ballerina/io;

// public function main() {
//     io:println("Hello, World!");
// }

import ballerina/http;

service / on new http:Listener(8089) {

    resource function get hello(http:Caller caller, http:Request req) returns error? {
        http:Response response = new;
        response.statusCode = 200;
        response.setTextPayload("Hello World");
        check caller->respond(response);
    }
}
