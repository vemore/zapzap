
const { decks } = require('cards');
const { Party } = require('./party.js');
//const { player } = require('./player.js');
const { print_players_hands, json_hand, check_play, get_card_from_id, get_card_id, get_cards_from_ids } = require('./utils.js');

// Create a standard 52 card deck + 2 jokers
const deck = new decks.StandardDeck({ jokers: 2 });

// Create party
const party = new Party(deck);

// Add players
party.add_player("Vincent");
party.add_player("Thibaut");
party.add_player("Simon  ");
party.add_player("Lyo    ");
party.add_player("Laurent");

// Start new round with 5 cards
var round = party.start_round(5, party.players[0]);

// print party status
print_players_hands(party.players);
console.log("Turn : "+ party.current_round.turn);

var express = require('express');
var app = express();
app.use('/node_modules/deck-of-cards', express.static('node_modules/deck-of-cards'));
app.use('/node_modules/jquery/dist', express.static('node_modules/jquery/dist'));
app.use('/public', express.static('public'));



app.get('/game', function(req, res) {
    res.setHeader('Content-Type', 'text/json');
    //var draw_card = deck.draw()[0];
    var draw_len = deck.remainingLength;
    res.send(JSON.stringify({"nb_card_back": draw_len, "cards_front": json_hand(round.last_cards_played)}));
    round.next_turn();
});


app.get('/', function(req, res) {
    res.render('hand.ejs', {"player": req.query.id});
});

app.get('/player/:id/hand', function(req, res) {
    res.setHeader('Content-Type', 'text/json');
    res.send(JSON.stringify(json_hand(party.players[req.params.id].hand)));
});

// PLAY
app.get('/player/:id/play', function(req, res) {
    var ret = true;

    // parse request
    var cards = get_cards_from_ids(req.query.cards, party.deck);
    var player = party.players[req.params.id];

    // check played cards
    if (check_play(cards, player)) {
        // remove cards from player hand
        player.play(cards);
        // play card on discard pile
        party.current_round.play_cards(cards);
    } else {
        ret = false;
    }

    res.setHeader('Content-Type', 'text/json');
    res.send(JSON.stringify(json_hand(party.players[req.params.id].hand)));
});


// DRAW
app.get('/player/:id/draw', function(req, res) {
    var ret = true;

    // parse request
    var card = undefined;
    if (req.query.card!="deck")
        card = get_card_from_id(req.query.card);
    var player = party.players[req.params.id];

    card = party.current_round.draw(card);
    player.draw(card);

    res.setHeader('Content-Type', 'text/json');
    res.send(JSON.stringify({draw: get_card_id(card), hand: json_hand(party.players[req.params.id].hand)}));
});



app.get('/party', function(req, res) {
    res.setHeader('Content-Type', 'text/json');
    res.send(party.json_string);
});

app.use(function(req, res, next){
    res.setHeader('Content-Type', 'text/plain');
    res.status(404).send('Page introuvable !');
});

app.listen(8080);
console.log("Play here : http://localhost:8080/?id=2");