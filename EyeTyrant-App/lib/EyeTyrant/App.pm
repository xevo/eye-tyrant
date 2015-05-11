package EyeTyrant::App;

use strict;
use warnings;

use JSON;
use Dancer2;
use Data::Dumper;
use Dancer2::Template::TemplateToolkit;
use lib "..";
use EyeTyrant::DataObjects::Character::Manager;
use EyeTyrant::DataObjects::Monster;
use EyeTyrant::DataObjects::Monster::Manager;
use EyeTyrant::DataObjects::Encounter;
use EyeTyrant::DataObjects::Encounter::Manager;
use EyeTyrant::DataObjects::MonsterEncounterMap;
use EyeTyrant::DataObjects::MonsterEncounterMap::Manager;
use Rose::DB::Object::Helpers qw( as_tree as_json );

our $VERSION = '0.1';

get '/' => sub {
    my $characters = EyeTyrant::DataObjects::Character::Manager->get_objects(
        query => [
            is_active => 1,
        ],
    );
    my $encounter = EyeTyrant::DataObjects::Encounter::Manager->get_objects(
        sort_by => 'id DESC',
        limit   => 1,
    )->[0];
    my $monsters = EyeTyrant::DataObjects::Monster::Manager->get_objects(
        require_objects => [qw(experience)],
    );
    my $monster_participants = EyeTyrant::DataObjects::MonsterEncounterMap::Manager->get_objects(
        query => [
            encounter_id => $encounter->id,
        ],
        require_objects => [qw(monster.experience)],
    );

    my @participants;
    my @sorted_participants;
    my $total_exp = 0;
    my $character_exp = 0;
    my $mob_number = 0;

    foreach my $character (@$characters) {
        push @participants, {
            name       => $character->name,
            initiative => $character->initiative + 0,
            damage     => $character->damage,
            id         => $character->id,
            type       => "character",
        };
    };

    foreach my $monster (@$monster_participants) {
        $mob_number += 1;
        push @participants, {
            name       => $monster->monster->name . ' ' . $mob_number,
            initiative => $monster->initiative + 0,
            hitpoints  => $monster->hitpoints,
            damage     => $monster->damage,
            id         => $monster->id,
            monster_id => $monster->monster_id,
            type       => "monster",
            is_active  => $monster->is_active,
        };

        $total_exp += $monster->monster->experience->exp;
    };

    @sorted_participants = sort { $b->{initiative} <=> $a->{initiative} } @participants;

    $character_exp = $total_exp / scalar @$characters;

    template 'index', {
        'participants'  => \@sorted_participants,
        'total_exp'     => $total_exp,
        'character_exp' => $character_exp,
    };
};

get '/search-monster/' => sub {
    my $monsters = EyeTyrant::DataObjects::Monster::Manager->get_objects (
        query => [
            name => { like => ['%'.params->{search}.'%'] }
        ],
        sort_by => 'name ASC',
    );

    template 'monster', {
        'monsters' => $monsters,
    };

};

get '/autocomplete-monster/' => sub {
    content_type 'application/json';

    my $monsters = EyeTyrant::DataObjects::Monster::Manager->get_objects (
        query => [
            name => { like => ['%'.params->{term}.'%']}
        ],
        sort_by => 'name ASC',
    );

    my $monster_map = [ map { {label => $_->name, value => $_->id } } @$monsters ];
    return to_json ($monster_map);
};

get '/get-monster/' => sub {
    my $monsters = EyeTyrant::DataObjects::Monster::Manager->get_objects (
        query => [
            id => params->{id},
        ],
        sort_by => 'name ASC',
        require_objects => [qw(experience)],
    )->[0];


    template 'monster', {
        'monsters' => $monsters,
    };


};

post '/add-monster/' => sub {
    my $encounter = EyeTyrant::DataObjects::Encounter::Manager->get_objects(
        sort_by => 'id DESC',
        limit   => 1,
    )->[0];

    my $monster = EyeTyrant::DataObjects::Monster::Manager->get_objects (
        query => [
            id => params->{id},
        ],
        sort_by => 'name ASC',
        require_objects => [qw(experience)],
    )->[0];

    my $hitpoints = $monster->{hp};
    my ($hp_to_calculate) = ($hitpoints =~ /\(([^\)]+)\)/);
    my ($multiplier, $dice, $base) = ($hp_to_calculate =~ /\d{1,3}/g);
    my $hp = $base;

    for (my $i=0; $i < $multiplier; $i++) {
        $hp += int(rand($dice)+1);
    }

    my $new_encounter_map = EyeTyrant::DataObjects::MonsterEncounterMap->new(
        encounter_id => $encounter->id,
        monster_id   => params->{id},
        hitpoints    => $hp,
        damage       => 0,
        initiative   => 0,
        is_active    => 1,
    );

    $new_encounter_map->save();

    redirect '/';
};

get '/new-encounter/' => sub {
    my $encounter = EyeTyrant::DataObjects::Encounter->new()->save();
    my $characters = EyeTyrant::DataObjects::Character::Manager->get_objects(
        query => [
            is_active => 1,
        ],
    );

    foreach my $character (@$characters) {
        $character->encounter_id($encounter->id);
        $character->initiative(0);
        $character->save();
    }

    redirect '/';
};

post '/update-character/' => sub {
    my $character = EyeTyrant::DataObjects::Character::Manager->get_objects(
        query => [
            is_active => 1,
            id        => params->{id},
        ],
        limit => 1,
    )->[0];

    $character->initiative(params->{inish});
    $character->damage(params->{damage} + params->{new_damage});
    $character->save();

    redirect '/';
};

post '/update-monster/' => sub {
    my $monster = EyeTyrant::DataObjects::MonsterEncounterMap::Manager->get_objects(
        query => [
            id         => params->{id},
            monster_id => params->{monster_id},
        ],
        limit => 1,
    )->[0];

    $monster->damage($monster->damage + params->{new_damage});
    if ($monster->damage >= $monster->hitpoints) {
        $monster->is_active(0);
    }
    $monster->initiative(params->{inish});
    $monster->save();

    redirect '/';
};

get '/initiative/' => sub {
    my $characters = EyeTyrant::DataObjects::Character::Manager->get_objects(
        query => [
            is_active => 1,
        ],
    );
    my $encounter = EyeTyrant::DataObjects::Encounter::Manager->get_objects(
        sort_by => 'id DESC',
        limit   => 1,
    )->[0];

    my $monsters = EyeTyrant::DataObjects::Monster::Manager->get_objects(
        require_objects => [qw(experience)],
    );
    my $monster_participants = EyeTyrant::DataObjects::MonsterEncounterMap::Manager->get_objects(
        query => [
            encounter_id => $encounter->id,
        ],
        require_objects => [qw(monster.experience)],
    );

    my @participants;
    my @sorted_participants;
    my $total_exp = 0;
    my $character_exp = 0;
    my $mob_number = 0;

    foreach my $character (@$characters) {
        push @participants, {
            name       => $character->name,
            initiative => $character->initiative + 0,
            damage     => $character->damage,
            id         => $character->id,
            image_uri  => $character->image_uri,
            type       => "character",
        };
    };

    foreach my $monster (@$monster_participants) {
        $mob_number += 1;
        push @participants, {
            name       => $monster->monster->name . ' ' . $mob_number,
            initiative => $monster->initiative + 0,
            hitpoints  => $monster->hitpoints,
            damage     => $monster->damage,
            id         => $monster->id,
            monster_id => $monster->monster_id,
            type       => "monster",
            is_active  => $monster->is_active,
        };

        $total_exp += $monster->monster->experience->exp;
    };

    @sorted_participants = sort { $b->{initiative} <=> $a->{initiative} } @participants;

    $character_exp = $total_exp / scalar @$characters;

    template 'initiative', {
        'participants'  => \@sorted_participants,
        'total_exp'     => $total_exp,
        'character_exp' => $character_exp,
    };
};

true;
