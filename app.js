
const { decks } = require('cards');
const { Party } = require('./party.js');
//const { player } = require('./player.js');
const { print_players_hands, json_hand, parse_cards_arg } = require('./utils.js');

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

app.get('/player/:id/play', function(req, res) {
    var ret = true;
    var cards = parse_cards_arg(req.query.cards);
    var player = party.players[req.params.id];
    if (!check_play(cards)) {
        last_card_played = player.play(cards);
    } else {
        ret = false;
    }


    res.setHeader('Content-Type', 'text/json');
    res.send(JSON.stringify({"ret" : ret}));
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