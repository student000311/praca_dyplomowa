package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"strconv"

	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	ds "github.com/ipfs/go-datastore"
	dsync "github.com/ipfs/go-datastore/sync"
	"github.com/libp2p/go-libp2p"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	rhost "github.com/libp2p/go-libp2p/p2p/host/routed"
	"github.com/mr-tron/base58/base58"
	ma "github.com/multiformats/go-multiaddr"
	// gologging "github.com/whyrusleeping/go-logging"
)

type CommunicatorHost struct {
	sync.Mutex
	ProfileDbId         int                         `json:"profile_db_id"`
	ProfilePrivateKey   string                      `json:"profile_private_key"`
	Host                *rhost.RoutedHost           `json:"-"`
	CommunicatorStreams map[int]*CommunicatorStream `json:"-"`
}

type CommunicatorStream struct {
	sync.Mutex
	ContactDbId   int            `json:"contact_db_id"`
	ContactPeerId string         `json:"contact_peer_id"`
	Stream        network.Stream `json:"-"`
}

var communicatorHosts = make(map[int]*CommunicatorHost)
var communicatorHostsMutex sync.Mutex

type Message struct {
	CreationTimestamp int    `json:"creation_timestamp"`
	Type              string `json:"type"`
	File              string `json:"file"`
	Text              string `json:"text"`
	Markdown          bool   `json:"markdown"`
}

type Addressing struct {
	SenderDbId   int `json:"sender_db_id"`
	ReceiverDbId int `json:"receiver_db_id"`
}

var backendPort *int
var frontendPort *int

func main() {
	backendPort = flag.Int("backend-port", 0, "")
	frontendPort = flag.Int("frontend-port", 0, "")
	flag.Parse()

	http.HandleFunc("/get_new_keys_and_peer_id", getNewKeysAndPeerId)
	http.HandleFunc("/add_connection", addConnection)
	http.HandleFunc("/remove_connection", removeConnection)

	http.HandleFunc("/send_message", sendMessage)

	fmt.Printf("Backend is running on port: %d", *backendPort)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", *backendPort), nil))
}

///////////////////////////////////////////////
////////////////// HOST
///////////////////////////////////////////////

// makeRoutedHost creates a LibP2P host. It will bootstrap using the
// provided PeerInfo
func makeRoutedHost(privateKey crypto.PrivKey) (*rhost.RoutedHost, error) {
	opts := []libp2p.Option{
		libp2p.ListenAddrStrings(fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", 0)),
		libp2p.Identity(privateKey),
		libp2p.DefaultTransports,
		libp2p.DefaultMuxers,
		libp2p.DefaultSecurity,
		libp2p.NATPortMap(),
		libp2p.DefaultEnableRelay,
	}

	ctx := context.Background()

	basicHost, err := libp2p.New(opts...)
	if err != nil {
		return nil, err
	}

	// Construct a datastore (needed by the DHT). This is just a simple, in-memory thread-safe datastore.
	dstore := dsync.MutexWrap(ds.NewMapDatastore())

	// Make the DHT
	dht := dht.NewDHT(ctx, basicHost, dstore)

	// Make the routed host
	routedHost := rhost.Wrap(basicHost, dht)

	// connect to the global ipfs nodes
	err = bootstrapConnect(ctx, routedHost, IPFS_PEERS)
	if err != nil {
		return nil, err
	}

	// Bootstrap the host
	err = dht.Bootstrap(ctx)
	if err != nil {
		return nil, err
	}

	// Build host multiaddress
	hostAddr, _ := ma.NewMultiaddr(fmt.Sprintf("/ipfs/%s", routedHost.ID()))

	// Now we can build a full multiaddress to reach this host
	// by encapsulating both addresses:
	// addr := routedHost.Addrs()[0]
	addrs := routedHost.Addrs()
	log.Println("NODE ADDRESSES:")
	for _, addr := range addrs {
		log.Println(addr.Encapsulate(hostAddr))
	}

	return routedHost, nil
}

///////////////////////////////////////////////
////////////////// BOOTSTRAP
///////////////////////////////////////////////

var (
	IPFS_PEERS = convertPeers([]string{
		"/dnsaddr/sv15.bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
		"/dnsaddr/am6.bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
		"/dnsaddr/ny5.bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
		"/dnsaddr/sg1.bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
	})
)

// to parse the results of the command `ipfs id`
type IdOutput struct {
	ID              string
	PublicKey       string
	Addresses       []string
	AgentVersion    string
	ProtocolVersion string
}

func convertPeers(peers []string) []peer.AddrInfo {
	pinfos := make([]peer.AddrInfo, len(peers))
	for i, addr := range peers {
		maddr := ma.StringCast(addr)
		p, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			log.Fatalln(err)
		}
		pinfos[i] = *p
	}
	return pinfos
}

// code from the go-ipfs bootstrap process
func bootstrapConnect(ctx context.Context, ph host.Host, peers []peer.AddrInfo) error {
	if len(peers) < 1 {
		return errors.New("not enough bootstrap peers")
	}

	errs := make(chan error, len(peers))
	var wg sync.WaitGroup
	for _, p := range peers {

		// performed asynchronously because when performed synchronously, if
		// one `Connect` call hangs, subsequent calls are more likely to
		// fail/abort due to an expiring context.
		// Also, performed asynchronously for dial speed.

		wg.Add(1)
		go func(p peer.AddrInfo) {
			defer wg.Done()

			ph.Peerstore().AddAddrs(p.ID, p.Addrs, peerstore.PermanentAddrTTL)
			if err := ph.Connect(ctx, p); err != nil {
				errs <- err
				return
			}
			log.Printf("bootstrapped with %v", p.ID)
		}(p)
	}
	wg.Wait()

	// our failure condition is when no connection attempt succeeded.
	// So drain the errs channel, counting the results.
	close(errs)
	count := 0
	var err error
	for err = range errs {
		if err != nil {
			count++
		}
	}
	if count == len(peers) {
		return fmt.Errorf("failed to bootstrap. %s", err)
	}
	return nil
}

///////////////////////////////////////////////
////////////////// STREAM
///////////////////////////////////////////////

func handleStream(stream network.Stream) {
	log.Printf("stream opened with %s", stream.Conn().RemotePeer())

	go readData(&stream)
}

func readData(stream *network.Stream) {
	var reader = bufio.NewReader(*stream)
	for {
		log.Println("Reading from buffer...")
		var message Message
		err := json.NewDecoder(reader).Decode(&message)
		if err != nil {
			log.Println("Reading from buffer...FAILED:", err)
			return // TODO
		}
		log.Println("Reading from buffer...DONE")
		receiveMessage(stream, message)
	}
}

///////////////////////////////////////////////
//////////////////
///////////////////////////////////////////////

func getNewKeysAndPeerId(w http.ResponseWriter, r *http.Request) {
	type Response struct {
		PrivateKey string `json:"private_key"`
		PublicKey  string `json:"public_key"`
		PeerId     string `json:"peer_id"`
	}
	var privateKeyObject = _generatePrivateKey()
	var publicKeyObject = _getPubKey(privateKeyObject)
	var peerIdObject = _getID(publicKeyObject)

	privKeyBytes, err := crypto.MarshalPrivateKey(privateKeyObject)
	if err != nil {
		panic(err)
	}
	var privateKey = base58.Encode(privKeyBytes)

	publicKeyBytes, err := crypto.MarshalPublicKey(publicKeyObject)
	if err != nil {
		panic(err)
	}
	var publicKey = base58.Encode(publicKeyBytes)

	response := Response{
		PrivateKey: privateKey,
		PublicKey:  publicKey,
		PeerId:     peerIdObject.String(),
	}

	jsonResponse, err := json.Marshal(response)
	if err != nil {
		http.Error(w, "Error encoding JSON", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	w.WriteHeader(http.StatusOK)
	w.Write(jsonResponse)
}

func addConnection(w http.ResponseWriter, r *http.Request) {
	var isNewHost bool = false
	var isNewStream bool = false
	var newHost *rhost.RoutedHost
	var exist bool

	var newConnection struct {
		ProfileDbId       int    `json:"profile_db_id"`
		ProfilePrivateKey string `json:"profile_private_key"`
		ContactDbId       int    `json:"contact_db_id"`
		ContactPeerId     string `json:"contact_peer_id"`
	}

	err := json.NewDecoder(r.Body).Decode(&newConnection)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	communicatorHostsMutex.Lock()
	_, exist = communicatorHosts[newConnection.ProfileDbId]
	if !exist {
		communicatorHosts[newConnection.ProfileDbId] = &CommunicatorHost{
			ProfileDbId:         newConnection.ProfileDbId,
			ProfilePrivateKey:   newConnection.ProfilePrivateKey,
			Host:                nil,
			CommunicatorStreams: make(map[int]*CommunicatorStream),
		}
		isNewHost = true
	}
	_, exist = communicatorHosts[newConnection.ProfileDbId] // we need this check here cause Go's error handling
	if exist {
		communicatorHosts[newConnection.ProfileDbId].Mutex.Lock()
		_, exist = communicatorHosts[newConnection.ProfileDbId].CommunicatorStreams[newConnection.ContactDbId]
		if exist {
			w.WriteHeader(http.StatusAlreadyReported)
			return
		} else {
			communicatorHosts[newConnection.ProfileDbId].CommunicatorStreams[newConnection.ContactDbId] = &CommunicatorStream{
				ContactDbId:   newConnection.ContactDbId,
				ContactPeerId: newConnection.ContactPeerId,
				Stream:        nil,
			}
			isNewStream = true
		}
		communicatorHosts[newConnection.ProfileDbId].Mutex.Unlock()
	}
	communicatorHostsMutex.Unlock()

	w.WriteHeader(http.StatusOK) // TODO

	if isNewHost {
		// convert Base64 string to bytes
		privKeyBytes, err := base58.Decode(newConnection.ProfilePrivateKey)
		if err != nil {
			panic(err)
		}
		// unmarshal the private key from bytes
		privateKey, err := crypto.UnmarshalPrivateKey(privKeyBytes)
		if err != nil {
			panic(err)
		}

		newHost, err = makeRoutedHost(privateKey)
		if err != nil {
			log.Fatal(err)
		}
		newHost.SetStreamHandler("/messaging/1.0.0", handleStream)

		communicatorHostsMutex.Lock()
		communicatorHost, exist := communicatorHosts[newConnection.ProfileDbId]
		if exist {
			communicatorHost.Mutex.Lock()
			if communicatorHost.Host == nil { // in case of repeated requests
				communicatorHost.Host = newHost
			}
			communicatorHost.Mutex.Unlock()
		}
		communicatorHostsMutex.Unlock()
	}

	if isNewStream {
		var stream network.Stream
		log.Println("Attempting to dial the guest peer...")
		for {
			guestID, err := peer.Decode(newConnection.ContactPeerId)
			if err != nil {
				log.Fatalln(err)
			}

			err = nil
			communicatorHostsMutex.Lock()
			communicatorHost, exist := communicatorHosts[newConnection.ProfileDbId]
			if exist {
				communicatorHost.Mutex.Lock()
				if communicatorHost.Host != nil {
					stream, err = communicatorHost.Host.NewStream(context.Background(), guestID, "/messaging/1.0.0")
				}
				communicatorHost.Mutex.Unlock()
			}
			communicatorHostsMutex.Unlock()
			if err != nil {
				log.Printf("Attempting to dial the guest peer...FAILED: %s\nRetry in 3 seconds", err)
				time.Sleep(time.Second * 3)
				continue
			}

			// handle the stream if dialing was successful
			communicatorHostsMutex.Lock()
			communicatorHost, exist = communicatorHosts[newConnection.ProfileDbId]
			if exist {
				communicatorHost.Mutex.Lock()
				communicatorStream, exist := communicatorHost.CommunicatorStreams[newConnection.ContactDbId]
				if exist {
					if communicatorStream.Stream == nil {
						log.Println("Handling stream...")
						communicatorStream.Stream = stream
						handleStream(stream)
						log.Println("Handling stream...DONE")
					}
				}
				communicatorHost.Mutex.Unlock()
			}
			communicatorHostsMutex.Unlock()

			break // exit after successfully establishing the connection
		}
		log.Println("Attempting to dial the guest peer...DONE")
	}
}

func removeConnection(w http.ResponseWriter, r *http.Request) {
	var exists bool
	var connection struct {
		ProfileDbId int `json:"profile_db_id"`
		ContactDbId int `json:"contact_db_id"`
	}

	err := json.NewDecoder(r.Body).Decode(&connection)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	communicatorHostsMutex.Lock()
	defer communicatorHostsMutex.Unlock()

	communicatorHost, exists := communicatorHosts[connection.ProfileDbId]
	if !exists {
		w.WriteHeader(http.StatusNotFound)
		return
	} else {
		communicatorHost.Mutex.Lock()
		communicatorStream, exists := communicatorHost.CommunicatorStreams[connection.ContactDbId]
		if !exists {
			w.WriteHeader(http.StatusNotFound)
			return
		} else {
			communicatorStream.Mutex.Lock()
			if communicatorStream.Stream != nil {
				err := communicatorStream.Stream.Close()
				if err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
			}
			communicatorStream.Mutex.Unlock()
			delete(communicatorHost.CommunicatorStreams, connection.ContactDbId)
		}
		communicatorHost.Mutex.Unlock()
		if len(communicatorHost.CommunicatorStreams) == 0 { // TODO possible race
			if communicatorHost.Host != nil {
				communicatorHost.Host.Close()
			}
			delete(communicatorHosts, connection.ProfileDbId)
		}
	}

	w.WriteHeader(http.StatusOK)
}

func sendMessage(w http.ResponseWriter, r *http.Request) {
	var addressing Addressing
	var message Message
	var data struct {
		Message    Message    `json:"message"`
		Addressing Addressing `json:"addressing"`
	}
	data.Message = message
	data.Addressing = addressing

	err := json.NewDecoder(r.Body).Decode(&data)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var streamIsNil bool = false
	for {
		communicatorHostsMutex.Lock()
		// TODO host is not initiated
		communicatorHost, exists := communicatorHosts[data.Addressing.SenderDbId]
		if !exists {
			fmt.Println("ERROR: Host not found")
			w.WriteHeader(http.StatusNotFound)
			return
		} else {
			communicatorHost.Mutex.Lock()
			communicatorStream, exists := communicatorHost.CommunicatorStreams[data.Addressing.ReceiverDbId]
			if !exists {
				fmt.Println("ERROR: Stream not found")
				w.WriteHeader(http.StatusNotFound)
				return
			} else {
				communicatorStream.Mutex.Lock()
				// TODO if nil - wait
				if communicatorStream.Stream == nil {
					streamIsNil = true
				} else {
					var writer = bufio.NewWriter(communicatorStream.Stream)

					err = json.NewEncoder(writer).Encode(data.Message)
					if err != nil {
						fmt.Println("Error writing to buffer:", err)
						continue
					}

					err = writer.Flush()
					if err != nil {
						fmt.Println("Error flushing buffer:", err)
						continue
					}
				}
				communicatorStream.Mutex.Unlock()
			}
			communicatorHost.Mutex.Unlock()
		}
		communicatorHostsMutex.Unlock()
		if streamIsNil {
			log.Println("Stream is unaccessible, retying to send message")
			time.Sleep(time.Second * 3)
			continue
		} else {
			break
		}
	}

	w.WriteHeader(http.StatusOK)
}

func receiveMessage(streamPtr *network.Stream, message Message) {
	var addressing Addressing
	var data struct {
		Message    Message    `json:"message"`
		Addressing Addressing `json:"addressing"`
	}
	data.Message = message
	stream := *streamPtr

	communicatorHostsMutex.Lock()
	for _, communicatorHost := range communicatorHosts {
		communicatorHost.Mutex.Lock()
		for _, communicatorStream := range communicatorHost.CommunicatorStreams {
			communicatorStream.Mutex.Lock()
			if communicatorStream.Stream.Conn().RemotePeer() == stream.Conn().RemotePeer() {
				addressing.SenderDbId = communicatorStream.ContactDbId
				addressing.ReceiverDbId = communicatorHost.ProfileDbId
				data.Addressing = addressing

				byteData, err := json.Marshal(data)
				if err != nil {
					log.Printf("Error marshalling JSON: %v", err)
					return
				}

				_, err = http.Post("http://localhost:"+strconv.Itoa(*frontendPort)+"/receive_message", "application/json", bytes.NewBuffer(byteData))
				if err != nil {
					log.Printf("Error sending request to frontend: %v", err)
					return
				}
			} else {
				log.Println("No stream found")
			}
			communicatorStream.Mutex.Unlock()
		}
		communicatorHost.Mutex.Unlock()
	}
	communicatorHostsMutex.Unlock()
}
