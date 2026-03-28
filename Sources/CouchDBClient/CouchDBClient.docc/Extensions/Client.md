# ``CouchDBClient/CouchDBClient``

A powerful and flexible CouchDB client for Swift, designed to simplify database interactions using Swift Concurrency.

## Overview

`CouchDBClient` provides a robust set of tools for interacting with CouchDB databases. It supports common database operations such as creating, deleting, and querying databases and documents. Built with Swift Concurrency, it ensures efficient and modern asynchronous programming.

This client is fully compatible with SwiftNIO, making it ideal for both server-side and client-side Swift applications.

## Topics

### Initialization
- ``init(config:httpClient:)``
- ``shutdown()``

### Database Management
- ``getAllDBs(eventLoopGroup:)``  
- ``createDB(_:eventLoopGroup:)``  
- ``deleteDB(_:eventLoopGroup:)``  
- ``dbExists(_:eventLoopGroup:)``  

### Document Operations
- ``get(fromDB:uri:queryItems:eventLoopGroup:)``  
- ``get(fromDB:uri:queryItems:dateDecodingStrategy:eventLoopGroup:)``  
- ``insert(dbName:body:eventLoopGroup:)``  
- ``insert(dbName:doc:dateEncodingStrategy:eventLoopGroup:)``  
- ``update(dbName:doc:dateEncodingStrategy:eventLoopGroup:)``  
- ``update(dbName:uri:body:eventLoopGroup:)``  
- ``delete(fromDb:doc:eventLoopGroup:)``  
- ``delete(fromDb:uri:rev:eventLoopGroup:)``  

### Querying and Indexes
- ``find(inDB:body:eventLoopGroup:)``  
- ``find(inDB:query:dateDecodingStrategy:eventLoopGroup:)``  
- ``listIndexes(inDB:eventLoopGroup:)``
- ``createIndex(inDB:index:eventLoopGroup:)``
- ``explain(inDB:query:eventLoopGroup:)``

### Attachments
- ``uploadAttachment(dbName:docId:attachmentName:data:contentType:rev:eventLoopGroup:)``
- ``downloadAttachment(dbName:docId:attachmentName:eventLoopGroup:)``
- ``deleteAttachment(dbName:docId:attachmentName:rev:eventLoopGroup:)``
