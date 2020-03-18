
const { decks } = require('cards');

// Create a standard 52 card deck + 2 jokers
const deck = new decks.StandardDeck({ jokers: 2 });

const nb_player = 4;
const nb_cards_in_hand = 7;
const player_hands = [];

function print_hand(hand) {
    var str_hand = "";
    hand.forEach(function(card){
        str_hand += card.rank.shortName + (card.suit.unicode!=null?card.suit.unicode:"") + "\t";
    });
    return str_hand;
}

function print_players_hands(player_hands) {

    player_hands.forEach(function(hand, index){
        console.log("Player " + index + " : " + print_hand(hand));
    });
    return;
}

function get_card_id(card) {
    var card_id = 0;
    switch (card.suit.unicode) {
        case '♠': card_id = 0; break;
        case '♥': card_id = 13; break;
        case '♣': card_id = 2*13; break;
        case '♦': card_id = 3*13; break;
        default : card_id = 4*13; 
    }
    switch (card.rank.shortName) {
        case 'A': card_id += 0; break;
        case 'J': card_id += 10; break;
        case 'Q': card_id += 11; break;
        case 'K': card_id += 12; break;
        case 'Jocker': card_id += 1; break;
        default : card_id += card.rank.shortName-1; 
    }
    return card_id;
}

function json_hand(hand) {
    var json_ret = []
    hand.forEach(function(card){
        json_ret.push(get_card_id(card));
    });
    console.log(json_ret);
    return json_ret;
}




// Shuffle the deck
deck.shuffleAll();

// Draw a hand of nb_cards_in_hand cards from the deck for each player
for (p=1;p<=nb_player;p++){
    player_hands[p] = deck.draw(nb_cards_in_hand);
}

// print partie status
print_players_hands(player_hands);

/*
var http = require('http');
var url = require('url');
var querystring = require('querystring');

var server = http.createServer(function(req, res) {
    var page = url.parse(req.url).pathname;
    var params = querystring.parse(url.parse(req.url).query);
    var player = undefined;
    if ('player' in params)
        player = params['player'];
    
    console.log(page);

    if (page == '/get_hand' && player!=undefined) {
        res.writeHead(200, {"Content-Type": "text/json"});
        res.write(JSON.stringify(player_hands[player]));
    }
    else {
        res.writeHead(404);
    }
    res.end();
});
server.listen(8080);
*/

var express = require('express');
var app = express();
app.use('/node_modules/deck-of-cards', express.static('node_modules/deck-of-cards'));
app.use('/node_modules/jquery/dist', express.static('node_modules/jquery/dist'));


app.get('/', function(req, res) {
    res.render('hand.ejs', {});
});

app.get('/player/:id/hand', function(req, res) {
    res.setHeader('Content-Type', 'text/json');
    res.send(JSON.stringify(json_hand(player_hands[req.params.id])));
});

app.use(function(req, res, next){
    res.setHeader('Content-Type', 'text/plain');
    res.status(404).send('Page introuvable !');
});

app.listen(8080);