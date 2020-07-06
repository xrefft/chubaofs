package main

import (
	"flag"
	"fmt"
	"github.com/hodgesds/iouring-go"
	"log"
	"math/rand"
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
	Write()

}
func Write(){
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
			_,err=r.Write(data)
			if err!=nil {
				log.Fatalf("write error %v",err)
			}
			atomic.AddUint64(&cnt,1)
		}
	}else {
		for {
			_,err=dst.Write(data)
			if err!=nil {
				log.Fatalf("write error %v",err)
			}
			atomic.AddUint64(&cnt,1)
		}
	}
	dst.Close()
}