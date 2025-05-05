package com.tab.crone;

import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/users")
public class UserController {

    private final UserRepository userRepo;

    public UserController(UserRepository userRepo) {
        this.userRepo = userRepo;
    }

    @PostMapping
    public User addUser(@RequestBody User user) {
        return userRepo.save(user);
    }

    @GetMapping
    public List<User> getAllUsers() {
        System.out.println("rus");
        List<User> users = userRepo.findAll();
        users.forEach(user -> {
            System.out.println(user.getName());
        });

        return  users;
    }


}
