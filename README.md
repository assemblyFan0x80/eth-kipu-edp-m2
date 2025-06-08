# Contrato Inteligente de Subasta (Auction)

Este contrato inteligente implementa una subasta en la que los usuarios pueden ofertar por un bien durante un tiempo determinado. Permite recibir ofertas, efectuar depósitos, reembolsos, y determinar al ganador. Las 



## 📋 Variables

| Variable           | Tipo          | Descripción                                                |
|--------------------|---------------|------------------------------------------------------------|
| `owner`            | `address`     | Dirección del propietario del contrato (quien despliega)  |
| `auctionEndTime`   | `uint`        | Timestamp que indica el final de la subasta.               |
| `highestBid`       | `uint`        | La mejor oferta recibida hasta el momento                  |
| `highestBidder`    | `address`     | Dirección del usuario que hizo la mejor oferta             |
| `offersByUser`     | `mapping`     | Mapea las direcciones de oferentes con sus ofertas (`Offer`) |
| `commission`       | `uint`        | La comisión a descontar al finalizar la subasta           |


## 🔔 Eventos

| Evento                 | Descripción                                                        |
|------------------------|-------------------------------------------------------------------|
| `NewBid(address bidder, uint amount)` | Emitido cada vez que un usuario realiza una oferta válida.  |
| `AuctionFinalized(address winner, uint winningBid)` | Emitido cuando finaliza la subasta, con el ganador y monto. |

---

## ⚙️ Funciones

### Constructor

Inicializa el contrato con la duracion de la subasta (en minutos)

```solidity
constructor(uint _biddingTime)

```

### bid
Maneja la lógica principal del contrato, gestionando las ofertas.
##### detalles de implementación
Se efectuan las validaciones de que la oferta sea un valor >0 y que quien esté ofertando no sea ya quien tiene la oferta más alta. Se establece el valor mínimo de la oferta válida (5% superior a la última más alta). Si se trata de la primera oferta, este valor es igual a 1. Si todo sale bien, se guarda la oferta y su timestamp en el array de ofertas. Se actualizan las variables de mejor oferente y oferta más alta. El uso de `address(0)` es para checkear que la variable `highestBidder` esté inicializada, ya que lo compara con un valor nulo o por defecto para una dirección. En el caso de que quien oferta sea el nuevo mejor postor, la oferta anterior (que perdió la puja) se suma al monto a reembolsar al anterior mejor postor. Finalmente se toma en cuenta la lógica del ejercicio de extender 10 minutos más la subasta si se efectua una nueva oferta mientras la subasta está activa y se emite el evento correspondiente a una nueva oferta.
#### Declaración
```solidity
function bid() public payable auctionActive
```



### getAllBids
Devuelve el array con todas las ofertas asociadas a un usuario.
#### Declaración
```solidity
function getAllBids(address user) external view returns (Offer[] memory) 
```

### getAllBidders
Devuelve el array con las direcciones de todos los oferentes.
#### Declaración
```solidity
function getAllBidders() external view returns (address[] memory)
```

### getWinner
Devuelve el ganador de la subasta y la cantidad de la puja ganadora. Se ejecuta solo cuando la subasta haya finalizado (via el modificador auctionEnded)
#### Declaración
```solidity
function getWinner() external view auctionEnded returns (address, uint)
```

### finalizeAuction
Funcion ejecutiva que da por terminada la subasta. Utiliza los modificadores onlyOwner y auctionEnded para garantizar que solo la puede ejecutar el dueño una vez que la subasta haya finalizado.
#### Declaración
```solidity
function finalizeAuction() external onlyOwner auctionEnded 
```


### refundLosingBids
Una vez que la subasta haya finalizado, transfiere los montos de las ofertas perdedoras a sus respectivas addresses.
#### Declaración
```solidity
function refundLosingBids() external auctionEnded
```


### partialWithdraw
Realiza los reembolsos de las ofertas anteriores a la última oferta válida que hizo el oferente. 
##### detalles de implementación
Recuperamos todas las ofertas de un usuario. El uso de storage es necesario para obtener una referencia directa al estado interno del contrato, para poder modificar definitivamente (poner a 0) las transacciones en el array `offersByUser`. No nos sirve obtener una copia porque en ese caso, sucesivas llamadas a la funcion seguirían determinando que hay ofertas por reembolsar. Con storage, hacemos que esos cambios (retiros) sean persistentes.
#### Declaración
```solidity
function partialWithdraw() external auctionActive
```

### timeLeft
Devuelve el tiempo restante de la subasta. 
#### Declaración
```solidity
function timeLeft() external view returns (uint)
```
