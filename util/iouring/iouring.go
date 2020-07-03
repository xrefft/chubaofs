package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net"
	"github.com/hodgesds/iouring-go"
	"net/http"
	_ "net/http/pprof"
	"os"
	"path"
	"sync/atomic"
	"time"
)

var (
	size=flag.Int64("size",64,"default write size")
	rootDir=flag.String("root","/data0","default write dir")
	uring=flag.Bool("iouring",true,"is used iouring")
	role=flag.String("role","server","default role")
	addr1=flag.String("remote","127.0.0.1:8888","default remote addr")
	port=8888
	ring *iouring.Ring
)

func inita(){
	var err error
	if *uring{
		ring, err = iouring.New(
			8192,
			&iouring.Params{
				Features: iouring.FeatNoDrop,
			},
			iouring.WithID(100000),
		)
		if err!=nil{
			log.Fatalf("init failed %v",err)
		}
		iouring.FastOpenAllowed()
	}
}


func init() {
	rand.Seed(time.Now().UnixNano())
}
var letterRunes = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
func RandStringRunes(n int) string {
	b := make([]rune, n)
	for i := range b {
		b[i] = letterRunes[rand.Intn(len(letterRunes))]
	}
	return string(b)
}

func main() {
	flag.Parse()

	inita()
	if *role=="server"{
		go func() {
			e := http.ListenAndServe(fmt.Sprintf(":%v", 8822), nil)
			if e != nil {
				log.Println(fmt.Errorf("cannot listen pprof %v err %v", 8822, e))
				os.Exit(1)
			}
		}()
		l,err:=Listen()
		if err!=nil {
			log.Fatal(err)
		}
		for {
			conn,err:=l.Accept()
			if err!=nil {
				log.Println(fmt.Sprintf("Accept error %v",err))
				continue
			}
			go Write(conn)
		}
	}else {
		go func() {
			e := http.ListenAndServe(fmt.Sprintf(":%v", 8821), nil)
			if e != nil {
				log.Println(fmt.Errorf("cannot listen pprof %v err %v", 8822, e))
				os.Exit(1)
			}
		}()
		conn,err:=Connect(*addr1)
		if err!=nil {
			log.Fatalf("connect error %v",err)
		}
		data:=RandStringRunes(int(*size))
		writeData:=([]byte)(data)
		for {
			_,err=conn.Write(writeData)
			if err!=nil{
				log.Println(fmt.Sprintf("write error %v",err))
				return
			}
		}
	}


}

func Listen()( l net.Listener,err error){
	if *uring{
		fmt.Printf("listening on port: %d\n", port)
		l, err := ring.SockoptListener(
			"tcp",
			fmt.Sprintf(":%d", port),
			func(err error) {
				log.Println(err)
			},
			iouring.SOReuseport,
		)
		if err != nil {
			log.Fatal(err)
		}
		return l,err
	}else {
		l,err=net.Listen("tcp",fmt.Sprintf(":%d", port))
		return l,err
	}
}

func Connect(addr string)(conn net.Conn,err error){
	conn,err=net.DialTimeout("tcp",addr,time.Second)
	if err!=nil {
		log.Println(fmt.Sprintf("Dail to %v err %v",addr,err))
		return
	}
	conn.(*net.TCPConn).SetNoDelay(true)
	conn.(*net.TCPConn).SetLinger(0)
	conn.(*net.TCPConn).SetKeepAlive(true)


	return
}

func Write(conn net.Conn){
	dst, err := os.OpenFile(path.Join(*rootDir,"1.txt"), os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		log.Fatal(err)
	}


	data:=make([]byte,*size)
	var cnt uint64
	go func() {
		ticker:=time.NewTicker(time.Second)
		for {
			select {
				case <-ticker.C:
					log.Println(fmt.Sprintf("iops is %v",atomic.LoadUint64(&cnt)))
					atomic.StoreUint64(&cnt,0)
			}
		}
	}()

	if *uring{
		r, err := ring.FileReadWriter(dst)
		if err!=nil {
			log.Fatal(err)
		}
		for {
			_,err=io.ReadFull(conn,data)
			if err!=nil {
				log.Fatalf("read from conn error %v",err)
			}
			fmt.Println(fmt.Sprintf("recive data %v",string(data)))
			_,err=r.Write(data)
			if err!=nil {
				log.Fatalf("write error %v",err)
			}
			atomic.AddUint64(&cnt,1)
		}
	}else {
		for {
			_,err=io.ReadFull(conn,data)
			if err!=nil {
				log.Fatalf("read from conn error %v",err)
			}
			_,err=dst.Write(data)
			if err!=nil {
				log.Fatalf("write error %v",err)
			}
			atomic.AddUint64(&cnt,1)
		}
	}
	dst.Close()
}