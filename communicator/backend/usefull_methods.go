package main

import (
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
)

func _generatePrivateKey() crypto.PrivKey { // TODO error handler
	privateKey, _, err := crypto.GenerateKeyPair(
		crypto.Ed25519, // Select your key type. Ed25519 are nice short
		-1,             // Select key length when possible (i.e. RSA).
	)
	if err != nil {
		panic(err)
	}
	return privateKey
}

func _getPubKey(privKey crypto.PrivKey) crypto.PubKey {
	return privKey.GetPublic()
}

func _getID(pubKey crypto.PubKey) peer.ID {
	// Generate the Peer ID from the public key
	peerID, err := peer.IDFromPublicKey(pubKey)
	if err != nil {
		// fmt.Println("Error generating Peer ID:", err)
		// return
		panic(err)
	}
	return peerID
}
