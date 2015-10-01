var numberOfRows = 1;

function sendMessage(content) {
  SamplePlugin.receiveMessage(content);
}

function printMessage(message) {
  numberOfRows++;
  $("#list").find("tbody").append(
    "<tr id=\"row-" + numberOfRows + "\">" +
    "<td><img class=\"avatar\" src=\"avatar_1.png\"></img></td>" +
    "<td>" + message + "</td>" +
    "</tr>"
    );
  $("#row-" + numberOfRows).click(function(e){
    var message = $($(this).children()[1]).text()
    sendMessage(message);
  })
}

$(document).ready(function(){
  $("tr").click(function(e){
    var message = $($(this).children()[1]).text()
    sendMessage(message);
  });
});